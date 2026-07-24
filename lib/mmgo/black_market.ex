defmodule MMGO.BlackMarket do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.BlackMarket.{Deal, ExpireDealWorker, Offer}
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Inventory.InventoryItem
  alias MMGO.Reputation
  alias MMGO.Repo
  alias MMGO.Travel.Clock
  alias MMGO.Worlds

  def list_active_offers(realm_id) when is_binary(realm_id) do
    Repo.all(
      from offer in Offer,
        where: offer.realm_id == ^realm_id and offer.status == :active,
        order_by: [asc: offer.inserted_at],
        preload: [:item_template, :seller_character]
    )
  end

  def list_deals_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from deal in Deal,
        where:
          deal.seller_character_id == ^character_id or deal.buyer_character_id == ^character_id,
        order_by: [desc: deal.inserted_at],
        preload: [:item_template, :seller_character, :buyer_character, :offer]
    )
  end

  def get_offer!(id) do
    Offer
    |> Repo.get!(id)
    |> Repo.preload([:item_template, :seller_character, :source_inventory_item])
  end

  def get_deal!(id) do
    Deal
    |> Repo.get!(id)
    |> Repo.preload([:item_template, :seller_character, :buyer_character, :offer])
  end

  def create_offer(%Character{} = seller, %InventoryItem{} = inventory_item, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    quantity = attrs["quantity"] || 1
    unit_price = attrs["unit_price"] || 0

    Repo.transaction(fn ->
      seller = lock_character!(seller.id)
      inventory_item = lock_inventory_item!(inventory_item.id)

      validate_offer_start!(seller, inventory_item, quantity, unit_price)

      offer =
        %Offer{}
        |> Offer.changeset(%{
          realm_id: seller.realm_id,
          seller_character_id: seller.id,
          source_inventory_item_id: inventory_item.id,
          item_template_id: inventory_item.item_template_id,
          quantity: quantity,
          unit_price: unit_price,
          total_price: quantity * unit_price,
          status: :active,
          listed_at: DateTime.utc_now(),
          metadata: attrs["metadata"] || %{}
        })
        |> Repo.insert!()

      %{offer: Repo.preload(offer, [:item_template, :seller_character, :source_inventory_item])}
    end)
    |> normalize_transaction_result()
  end

  def cancel_offer(%Offer{} = offer, %Character{} = seller) do
    Repo.transaction(fn ->
      offer = lock_offer!(offer.id)

      cond do
        offer.status != :active ->
          Repo.rollback(offer_changeset("offer is not active"))

        offer.seller_character_id != seller.id ->
          Repo.rollback(offer_changeset("offer does not belong to this character"))

        true ->
          offer
          |> Offer.changeset(%{status: :cancelled, cancelled_at: DateTime.utc_now()})
          |> Repo.update!()
      end
    end)
    |> normalize_transaction_result()
  end

  @doc "Returns the server-owned NPC detection odds and fine for one untaxed deal."
  def detection_terms(total_price, tax_rate_bps)
      when is_integer(total_price) and total_price > 0 and is_integer(tax_rate_bps) and
             tax_rate_bps >= 0 do
    config = config()
    base_chance = config[:detection_base_chance_bps] || 300
    price_scale = config[:detection_price_scale_bps] || 2
    max_chance = config[:detection_max_chance_bps] || 5_000
    fine_multiplier = config[:detection_fine_multiplier] || 3
    evaded_tax = div(total_price * tax_rate_bps, 10_000)

    %{
      chance_bps: min(base_chance + total_price * price_scale, max_chance),
      evaded_tax: evaded_tax,
      fine_amount: evaded_tax * fine_multiplier,
      fine_multiplier: fine_multiplier
    }
  end

  def accept_offer(%Offer{} = offer, %Character{} = buyer, opts \\ []) do
    accepted_at = Keyword.get(opts, :accepted_at, DateTime.utc_now())

    delivery_game_days =
      Keyword.get(opts, :delivery_game_days, config()[:delivery_game_days] || 7)

    Repo.transaction(fn ->
      offer = lock_offer!(offer.id)
      buyer = lock_character!(buyer.id)
      seller = lock_character!(offer.seller_character_id)

      validate_offer_acceptance!(offer, seller, buyer)

      {:ok, buyer_account} = Economy.ensure_character_account(buyer)
      {:ok, seller_account} = Economy.ensure_character_account(seller)

      case Economy.transfer(
             buyer_account,
             seller_account,
             offer.total_price,
             %{
               entry_type: "black_market",
               source: "black_market_offer",
               offer_id: offer.id,
               seller_character_id: seller.id,
               buyer_character_id: buyer.id
             }
           ) do
        {:ok, ledger_result} ->
          delivery_due_at = Clock.arrival_at(accepted_at, delivery_game_days)

          deal =
            %Deal{}
            |> Deal.changeset(%{
              realm_id: offer.realm_id,
              offer_id: offer.id,
              seller_character_id: seller.id,
              buyer_character_id: buyer.id,
              item_template_id: offer.item_template_id,
              quantity: offer.quantity,
              total_price: offer.total_price,
              status: :awaiting_delivery,
              paid_at: accepted_at,
              metadata: %{"delivery_due_at" => DateTime.to_iso8601(delivery_due_at)}
            })
            |> Repo.insert!()

          {deal, detection} = apply_detection!(deal, seller, opts)

          worker_job =
            %{"deal_id" => deal.id}
            |> ExpireDealWorker.new(
              schedule_in: max(DateTime.diff(delivery_due_at, DateTime.utc_now(), :second), 0)
            )
            |> Oban.insert!()

          updated_offer =
            offer
            |> Offer.changeset(%{status: :committed})
            |> Repo.update!()

          %{
            deal:
              Repo.preload(deal, [:item_template, :seller_character, :buyer_character, :offer]),
            offer: updated_offer,
            economy: ledger_result,
            detection: detection,
            worker_job: worker_job
          }

        {:error, %Changeset{} = changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def fulfill_deal(%Deal{} = deal, %Character{} = seller) do
    Repo.transaction(fn ->
      deal = lock_deal!(deal.id)
      seller = lock_character!(seller.id)
      buyer = lock_character!(deal.buyer_character_id)

      validate_fulfillment!(deal, seller)

      inventory_item =
        InventoryItem
        |> where(
          [item],
          item.character_id == ^seller.id and item.item_template_id == ^deal.item_template_id and
            item.quantity - item.reserved_quantity >= ^deal.quantity
        )
        |> order_by([item], asc: item.inserted_at)
        |> lock("FOR UPDATE")
        |> preload(:item_template)
        |> Repo.one()

      if is_nil(inventory_item) do
        Repo.rollback(deal_changeset("seller no longer has the promised goods"))
      end

      item_result = transfer_inventory!(inventory_item, buyer, deal.quantity)

      updated_deal =
        deal
        |> Deal.changeset(%{status: :fulfilled, fulfilled_at: DateTime.utc_now()})
        |> Repo.update!()

      updated_offer =
        deal.offer_id
        |> lock_offer!()
        |> Offer.changeset(%{status: :fulfilled, fulfilled_at: DateTime.utc_now()})
        |> Repo.update!()

      %{
        deal:
          Repo.preload(updated_deal, [:item_template, :seller_character, :buyer_character, :offer]),
        offer: updated_offer,
        item_result: item_result
      }
    end)
    |> normalize_transaction_result()
  end

  def default_deal(%Deal{} = deal, %Character{} = actor, reason \\ nil, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      deal = lock_deal!(deal.id)
      actor = lock_character!(actor.id)
      seller = lock_character!(deal.seller_character_id)
      validate_default!(deal, actor, now)

      apply_default!(deal, seller, reason, now)
    end)
    |> normalize_transaction_result()
  end

  @doc "Expires one overdue delivery idempotently for the durable Oban worker."
  def expire_deal_by_id(deal_id, opts \\ []) when is_binary(deal_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Repo.transaction(fn ->
      deal = lock_deal!(deal_id)

      cond do
        deal.status != :awaiting_delivery ->
          %{deal: deal, expired?: false}

        not delivery_due?(deal, now) ->
          Repo.rollback(deal_changeset("deal delivery deadline has not passed"))

        true ->
          seller = lock_character!(deal.seller_character_id)

          apply_default!(deal, seller, "delivery deadline expired", now)
          |> Map.put(:expired?, true)
      end
    end)
    |> normalize_transaction_result()
  end

  defp validate_offer_start!(
         %Character{} = seller,
         %InventoryItem{} = inventory_item,
         quantity,
         unit_price
       ) do
    cond do
      seller.id != inventory_item.character_id ->
        Repo.rollback(offer_changeset("inventory item does not belong to the seller"))

      quantity <= 0 ->
        Repo.rollback(offer_changeset("quantity must be greater than zero"))

      unit_price <= 0 ->
        Repo.rollback(offer_changeset("unit price must be greater than zero"))

      quantity > Inventory.available_quantity(inventory_item) ->
        Repo.rollback(offer_changeset("quantity exceeds the currently available inventory"))

      inventory_item.item_template.stackable == false and quantity != 1 ->
        Repo.rollback(offer_changeset("non-stackable items must be offered one at a time"))

      true ->
        :ok
    end
  end

  defp validate_offer_acceptance!(%Offer{} = offer, %Character{} = seller, %Character{} = buyer) do
    cond do
      offer.status != :active ->
        Repo.rollback(offer_changeset("offer is not active"))

      buyer.id == seller.id ->
        Repo.rollback(offer_changeset("seller cannot accept their own offer"))

      buyer.realm_id != offer.realm_id ->
        Repo.rollback(offer_changeset("buyer must belong to the same realm"))

      seller.realm_id != offer.realm_id ->
        Repo.rollback(offer_changeset("seller must belong to the same realm"))

      Repo.exists?(from deal in Deal, where: deal.offer_id == ^offer.id) ->
        Repo.rollback(offer_changeset("offer has already been claimed"))

      true ->
        :ok
    end
  end

  defp validate_fulfillment!(%Deal{} = deal, %Character{} = seller) do
    cond do
      deal.status != :awaiting_delivery ->
        Repo.rollback(deal_changeset("deal is not awaiting delivery"))

      deal.seller_character_id != seller.id ->
        Repo.rollback(deal_changeset("deal does not belong to this seller"))

      true ->
        :ok
    end
  end

  defp validate_default!(%Deal{} = deal, %Character{} = actor, now) do
    cond do
      deal.status != :awaiting_delivery ->
        Repo.rollback(deal_changeset("deal is not awaiting delivery"))

      actor.id == deal.seller_character_id ->
        :ok

      actor.id == deal.buyer_character_id and delivery_due?(deal, now) ->
        :ok

      actor.id == deal.buyer_character_id ->
        Repo.rollback(deal_changeset("deal delivery deadline has not passed"))

      true ->
        Repo.rollback(deal_changeset("deal does not belong to this character"))
    end
  end

  defp apply_default!(%Deal{} = deal, %Character{} = seller, reason, now) do
    updated_deal =
      deal
      |> Deal.changeset(%{
        status: :defaulted,
        defaulted_at: now,
        metadata: maybe_put_reason(deal.metadata || %{}, reason)
      })
      |> Repo.update!()

    updated_offer =
      deal.offer_id
      |> lock_offer!()
      |> Offer.changeset(%{status: :defaulted, defaulted_at: now})
      |> Repo.update!()

    {:ok, _crime_result} =
      Reputation.record_black_market_default(seller, deal.total_price, %{
        deal_id: deal.id,
        offer_id: deal.offer_id,
        buyer_character_id: deal.buyer_character_id,
        reason: reason
      })

    %{deal: updated_deal, offer: updated_offer}
  end

  defp apply_detection!(%Deal{} = deal, %Character{} = seller, opts) do
    tax_rate_bps = Worlds.realm_ruleset(deal.realm_id)["legal_market_tax_rate_bps"]
    terms = detection_terms(deal.total_price, tax_rate_bps)
    explicit_roll? = Keyword.has_key?(opts, :detection_roll)
    enabled? = explicit_roll? or config()[:detection_enabled] != false
    roll = if enabled?, do: detection_roll(opts), else: nil
    caught? = enabled? and roll < terms.chance_bps

    detection =
      terms
      |> Map.merge(%{caught?: caught?, roll: roll})

    detection_metadata = %{
      "caught" => caught?,
      "chance_bps" => terms.chance_bps,
      "roll" => roll,
      "evaded_tax" => terms.evaded_tax,
      "fine_amount" => terms.fine_amount,
      "fine_multiplier" => terms.fine_multiplier
    }

    updated_deal =
      deal
      |> Deal.changeset(%{
        metadata: Map.put(deal.metadata || %{}, "npc_detection", detection_metadata)
      })
      |> Repo.update!()

    if caught? do
      severity = min(10 + div(deal.total_price, 50), 50)

      {:ok, _crime_result} =
        Reputation.record_crime(Repo, seller, :black_market_detection, %{
          severity: severity,
          reputation_delta: -severity,
          fine_amount: terms.fine_amount,
          market_ban_game_days: max(div(severity, 2), 3),
          status: if(terms.fine_amount > 0, do: :open, else: :resolved),
          metadata: %{
            deal_id: deal.id,
            offer_id: deal.offer_id,
            evaded_tax: terms.evaded_tax,
            detection_chance_bps: terms.chance_bps,
            detection_roll: roll
          }
        })

      if terms.fine_amount > 0 do
        # Settle only what the offender can currently afford. The crime and
        # any remainder stay durable instead of rolling back the illegal deal.
        _ = Reputation.pay_fine(seller)
      end
    end

    {updated_deal, detection}
  end

  defp detection_roll(opts) do
    case Keyword.get(opts, :detection_roll) do
      roll when is_integer(roll) -> max(min(roll, 9_999), 0)
      _other -> :rand.uniform(10_000) - 1
    end
  end

  defp delivery_due?(%Deal{} = deal, now) do
    case Map.get(deal.metadata || %{}, "delivery_due_at") do
      due_at when is_binary(due_at) ->
        case DateTime.from_iso8601(due_at) do
          {:ok, parsed, _offset} -> DateTime.compare(now, parsed) != :lt
          _invalid -> true
        end

      _missing ->
        true
    end
  end

  defp transfer_inventory!(%InventoryItem{} = inventory_item, %Character{} = buyer, quantity) do
    item_template = Repo.preload(inventory_item, :item_template).item_template

    if item_template.stackable do
      remaining_quantity = inventory_item.quantity - quantity

      if remaining_quantity == 0 do
        Repo.delete!(inventory_item)
      else
        inventory_item
        |> InventoryItem.changeset(%{quantity: remaining_quantity})
        |> Repo.update!()
      end

      {:ok, granted_item} = Inventory.grant_item(buyer, item_template, %{quantity: quantity})
      granted_item
    else
      inventory_item
      |> InventoryItem.changeset(%{character_id: buyer.id})
      |> Repo.update!()
    end
  end

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_inventory_item!(inventory_item_id) do
    InventoryItem
    |> where([item], item.id == ^inventory_item_id)
    |> lock("FOR UPDATE")
    |> preload(:item_template)
    |> Repo.one!()
  end

  defp lock_offer!(offer_id) do
    Offer
    |> where([offer], offer.id == ^offer_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_deal!(deal_id) do
    Deal
    |> where([deal], deal.id == ^deal_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp maybe_put_reason(metadata, nil), do: metadata
  defp maybe_put_reason(metadata, reason), do: Map.put(metadata, "default_reason", reason)

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp config, do: Application.get_env(:mmgo, __MODULE__, [])

  defp offer_changeset(message) do
    %Offer{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp deal_changeset(message) do
    %Deal{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
