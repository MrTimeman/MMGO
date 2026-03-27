defmodule MMGO.Market do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Inventory.InventoryItem
  alias MMGO.Market.Listing
  alias MMGO.Repo

  def list_active_listings(realm_id) when is_binary(realm_id) do
    Repo.all(
      from listing in Listing,
        where: listing.realm_id == ^realm_id and listing.status == :active,
        order_by: [asc: listing.inserted_at],
        preload: [:item_template, :seller_character, :inventory_item]
    )
  end

  def get_listing!(id) do
    Listing
    |> Repo.get!(id)
    |> Repo.preload([:item_template, :seller_character, :buyer_character, :inventory_item])
  end

  def create_listing(%Character{} = seller, %InventoryItem{} = inventory_item, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    quantity = attrs["quantity"] || 1
    unit_price = attrs["unit_price"] || 0
    tax_rate_bps = attrs["tax_rate_bps"] || 0

    Repo.transaction(fn ->
      seller = lock_character!(seller.id)
      inventory_item = lock_inventory_item!(inventory_item.id)

      validate_listing_start!(seller, inventory_item, quantity, unit_price, tax_rate_bps)

      listing =
        %Listing{}
        |> Listing.changeset(%{
          realm_id: seller.realm_id,
          seller_character_id: seller.id,
          inventory_item_id: inventory_item.id,
          item_template_id: inventory_item.item_template_id,
          quantity: quantity,
          unit_price: unit_price,
          total_price: quantity * unit_price,
          tax_rate_bps: tax_rate_bps,
          status: :active,
          listed_at: DateTime.utc_now(),
          metadata: attrs["metadata"] || %{}
        })
        |> Repo.insert!()

      updated_inventory_item =
        inventory_item
        |> InventoryItem.changeset(%{
          reserved_quantity: inventory_item.reserved_quantity + quantity
        })
        |> Repo.update!()

      %{
        listing: Repo.preload(listing, [:item_template, :inventory_item]),
        inventory_item: updated_inventory_item
      }
    end)
    |> normalize_transaction_result()
  end

  def cancel_listing(%Listing{} = listing, %Character{} = seller) do
    Repo.transaction(fn ->
      listing = lock_listing!(listing.id)
      inventory_item = lock_inventory_item!(listing.inventory_item_id)

      cond do
        listing.status != :active ->
          Repo.rollback(listing_changeset("listing is not active"))

        listing.seller_character_id != seller.id ->
          Repo.rollback(listing_changeset("listing does not belong to this character"))

        true ->
          updated_inventory_item =
            inventory_item
            |> InventoryItem.changeset(%{
              reserved_quantity: inventory_item.reserved_quantity - listing.quantity
            })
            |> Repo.update!()

          updated_listing =
            listing
            |> Listing.changeset(%{status: :cancelled, cancelled_at: DateTime.utc_now()})
            |> Repo.update!()

          %{listing: updated_listing, inventory_item: updated_inventory_item}
      end
    end)
    |> normalize_transaction_result()
  end

  def purchase_listing(%Listing{} = listing, %Character{} = buyer) do
    Repo.transaction(fn ->
      listing = lock_listing!(listing.id)
      inventory_item = lock_inventory_item!(listing.inventory_item_id)
      buyer = lock_character!(buyer.id)
      seller = lock_character!(listing.seller_character_id)

      validate_purchase!(listing, inventory_item, seller, buyer)

      {:ok, buyer_account} = Economy.ensure_character_account(buyer)
      {:ok, seller_account} = Economy.ensure_character_account(seller)

      case Economy.taxed_transfer(
             buyer_account,
             seller_account,
             listing.total_price,
             listing.tax_rate_bps,
             %{
               entry_type: "purchase",
               source: "market_listing",
               listing_id: listing.id,
               seller_character_id: seller.id,
               buyer_character_id: buyer.id
             }
           ) do
        {:ok, ledger_result} ->
          item_result = transfer_listed_inventory!(inventory_item, buyer, listing.quantity)

          updated_listing =
            listing
            |> Listing.changeset(%{
              status: :sold,
              buyer_character_id: buyer.id,
              sold_at: DateTime.utc_now()
            })
            |> Repo.update!()

          %{listing: updated_listing, economy: ledger_result, item_result: item_result}

        {:error, %Changeset{} = changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  defp validate_listing_start!(
         %Character{} = seller,
         %InventoryItem{} = inventory_item,
         quantity,
         unit_price,
         tax_rate_bps
       ) do
    cond do
      seller.id != inventory_item.character_id ->
        Repo.rollback(listing_changeset("inventory item does not belong to the seller"))

      quantity <= 0 ->
        Repo.rollback(listing_changeset("quantity must be greater than zero"))

      unit_price <= 0 ->
        Repo.rollback(listing_changeset("unit price must be greater than zero"))

      tax_rate_bps < 0 or tax_rate_bps > 10_000 ->
        Repo.rollback(listing_changeset("tax rate must be between 0 and 10000 basis points"))

      Repo.exists?(
        from listing in Listing,
          where: listing.inventory_item_id == ^inventory_item.id and listing.status == :active
      ) ->
        Repo.rollback(listing_changeset("inventory item already has an active listing"))

      quantity > Inventory.available_quantity(inventory_item) ->
        Repo.rollback(listing_changeset("quantity exceeds the available inventory"))

      inventory_item.item_template.stackable == false and quantity != 1 ->
        Repo.rollback(listing_changeset("non-stackable items must be listed one at a time"))

      true ->
        :ok
    end
  end

  defp validate_purchase!(
         %Listing{} = listing,
         %InventoryItem{} = inventory_item,
         %Character{} = seller,
         %Character{} = buyer
       ) do
    cond do
      listing.status != :active ->
        Repo.rollback(listing_changeset("listing is not active"))

      buyer.id == seller.id ->
        Repo.rollback(listing_changeset("seller cannot buy their own listing"))

      buyer.realm_id != listing.realm_id ->
        Repo.rollback(listing_changeset("buyer must belong to the same realm"))

      seller.realm_id != listing.realm_id ->
        Repo.rollback(listing_changeset("seller must belong to the same realm"))

      listing.quantity > inventory_item.reserved_quantity ->
        Repo.rollback(listing_changeset("listed quantity is no longer reserved"))

      true ->
        :ok
    end
  end

  defp transfer_listed_inventory!(
         %InventoryItem{} = inventory_item,
         %Character{} = buyer,
         quantity
       ) do
    item_template = Repo.preload(inventory_item, :item_template).item_template

    if item_template.stackable do
      remaining_quantity = inventory_item.quantity - quantity
      remaining_reserved = inventory_item.reserved_quantity - quantity

      if remaining_quantity == 0 do
        Repo.delete!(inventory_item)
      else
        inventory_item
        |> InventoryItem.changeset(%{
          quantity: remaining_quantity,
          reserved_quantity: remaining_reserved
        })
        |> Repo.update!()
      end

      {:ok, granted_item} = Inventory.grant_item(buyer, item_template, %{quantity: quantity})
      granted_item
    else
      inventory_item
      |> InventoryItem.changeset(%{character_id: buyer.id, reserved_quantity: 0})
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

  defp lock_listing!(listing_id) do
    Listing
    |> where([listing], listing.id == ^listing_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp listing_changeset(message) do
    %Listing{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
