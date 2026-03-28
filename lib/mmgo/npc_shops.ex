defmodule MMGO.NPCShops do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Inventory.InventoryItem
  alias MMGO.NPCShops.{Offer, Shop}
  alias MMGO.Repo
  alias MMGO.Worlds.Location

  def list_shops_for_location(location_id) when is_binary(location_id) do
    Repo.all(
      from shop in Shop,
        where: shop.location_id == ^location_id and shop.status == :active,
        order_by: [asc: shop.inserted_at]
    )
  end

  def get_shop_by_code(location_id, code) when is_binary(location_id) and is_binary(code) do
    Shop
    |> Repo.get_by(location_id: location_id, code: code, status: :active)
    |> case do
      nil -> nil
      shop -> Repo.preload(shop, offers: [:item_template])
    end
  end

  def get_shop!(id), do: Shop |> Repo.get!(id) |> Repo.preload(offers: [:item_template])
  def get_offer!(id), do: Offer |> Repo.get!(id) |> Repo.preload([:shop, :item_template])

  def create_shop(%Location{} = location, attrs \\ %{}) do
    attrs =
      stringify_keys(attrs)
      |> Map.put("location_id", location.id)
      |> Map.put("realm_id", location.realm_id)

    %Shop{}
    |> Shop.changeset(attrs)
    |> Repo.insert()
  end

  def add_offer(%Shop{} = shop, attrs \\ %{}) do
    attrs = stringify_keys(attrs) |> Map.put("shop_id", shop.id)

    %Offer{}
    |> Offer.changeset(attrs)
    |> Repo.insert()
  end

  def buy(%Character{} = character, %Offer{} = offer, quantity \\ 1) when is_integer(quantity) do
    Repo.transaction(fn ->
      character = lock_character!(character.id)
      offer = get_offer!(offer.id)
      shop = get_shop!(offer.shop_id)
      validate_buy!(character, shop, offer, quantity)

      total_price = offer.buy_price * quantity
      {:ok, character_account} = Economy.ensure_character_account(character)
      treasury = Economy.treasury_account_for_realm(character.realm_id)

      {:ok, economy_result} =
        Economy.transfer(character_account, treasury, total_price, %{
          entry_type: "purchase",
          source: "npc_shop_buy",
          shop_id: shop.id,
          offer_id: offer.id
        })

      {:ok, item_result} =
        Inventory.grant_item(character, offer.item_template, %{
          quantity: quantity,
          durability: offer.item_durability
        })

      %{economy: economy_result, item_result: item_result}
    end)
    |> normalize_transaction_result()
  end

  def sell(
        %Character{} = character,
        %Offer{} = offer,
        %InventoryItem{} = inventory_item,
        quantity \\ 1
      )
      when is_integer(quantity) do
    Repo.transaction(fn ->
      character = lock_character!(character.id)
      offer = get_offer!(offer.id)
      shop = get_shop!(offer.shop_id)
      inventory_item = lock_inventory_item!(inventory_item.id)
      validate_sell!(character, shop, offer, inventory_item, quantity)

      payout = offer.sell_price * quantity
      treasury = Economy.treasury_account_for_realm(character.realm_id)
      {:ok, character_account} = Economy.ensure_character_account(character)

      {:ok, economy_result} =
        Economy.transfer(treasury, character_account, payout, %{
          entry_type: "reward",
          source: "npc_shop_sell",
          shop_id: shop.id,
          offer_id: offer.id
        })

      consume_inventory!(inventory_item, quantity)

      %{economy: economy_result, payout: payout}
    end)
    |> normalize_transaction_result()
  end

  def ensure_charity_fund_account(realm) do
    case Repo.get_by(Economy.EconomyAccount, realm_id: realm.id, owner_type: :charity_fund) do
      %Economy.EconomyAccount{} = account ->
        {:ok, account}

      nil ->
        %Economy.EconomyAccount{}
        |> Economy.EconomyAccount.changeset(%{
          realm_id: realm.id,
          owner_type: :charity_fund,
          current_balance: 0,
          metadata: %{"system" => "charity_fund"}
        })
        |> Repo.insert()
    end
  end

  def donate_to_charity(%Character{} = character, amount) when is_integer(amount) do
    with true <- amount > 0 do
      {:ok, character_account} = Economy.ensure_character_account(character)

      {:ok, charity_account} =
        ensure_charity_fund_account(Repo.get!(MMGO.Worlds.Realm, character.realm_id))

      Economy.transfer(character_account, charity_account, amount, %{
        entry_type: "tax",
        source: "charity_donation",
        character_id: character.id
      })
    else
      _ -> {:error, shop_changeset("donation amount must be greater than zero")}
    end
  end

  def pay_tuition(%Character{} = character, amount) when is_integer(amount) do
    with true <- amount > 0 do
      {:ok, character_account} = Economy.ensure_character_account(character)
      treasury = Economy.treasury_account_for_realm(character.realm_id)

      Economy.transfer(character_account, treasury, amount, %{
        entry_type: "purchase",
        source: "academy_tuition",
        character_id: character.id
      })
    else
      _ -> {:error, shop_changeset("tuition amount must be greater than zero")}
    end
  end

  defp validate_buy!(%Character{} = character, %Shop{} = shop, %Offer{} = offer, quantity) do
    cond do
      quantity <= 0 ->
        Repo.rollback(shop_changeset("quantity must be greater than zero"))

      character.current_location_id != shop.location_id ->
        Repo.rollback(shop_changeset("character must be at the shop location"))

      offer.buy_price <= 0 ->
        Repo.rollback(shop_changeset("offer cannot be purchased from this shop"))

      true ->
        :ok
    end
  end

  defp validate_sell!(
         %Character{} = character,
         %Shop{} = shop,
         %Offer{} = offer,
         %InventoryItem{} = inventory_item,
         quantity
       ) do
    cond do
      quantity <= 0 ->
        Repo.rollback(shop_changeset("quantity must be greater than zero"))

      character.current_location_id != shop.location_id ->
        Repo.rollback(shop_changeset("character must be at the shop location"))

      offer.sell_price <= 0 ->
        Repo.rollback(shop_changeset("shop is not buying this item"))

      inventory_item.character_id != character.id ->
        Repo.rollback(shop_changeset("inventory item does not belong to the character"))

      inventory_item.item_template_id != offer.item_template_id ->
        Repo.rollback(shop_changeset("inventory item does not match the shop offer"))

      quantity > Inventory.available_quantity(inventory_item) ->
        Repo.rollback(shop_changeset("quantity exceeds the available inventory"))

      true ->
        :ok
    end
  end

  defp consume_inventory!(inventory_item, quantity) do
    remaining_quantity = inventory_item.quantity - quantity

    if remaining_quantity == 0 do
      Repo.delete!(inventory_item)
    else
      inventory_item
      |> InventoryItem.changeset(%{
        quantity: remaining_quantity,
        reserved_quantity: inventory_item.reserved_quantity
      })
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
    |> Repo.one!()
    |> Repo.preload(:item_template)
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp shop_changeset(message) do
    %Shop{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
