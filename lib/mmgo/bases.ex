defmodule MMGO.Bases do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Bases.{Base, CompleteBaseBuildWorker, StorageItem}
  alias MMGO.Inventory
  alias MMGO.Inventory.InventoryItem
  alias MMGO.Notifications
  alias MMGO.Repo
  alias MMGO.Travel.Clock
  alias MMGO.Worlds.Location

  @city_storage_capacity 250
  @custom_storage_capacity 350

  def list_bases_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from base in Base,
        where: base.owner_character_id == ^character_id,
        order_by: [asc: base.inserted_at],
        preload: [:location]
    )
  end

  def get_base!(id) do
    Base
    |> Repo.get!(id)
    |> Repo.preload([:location, storage_items: :item_template])
  end

  def list_storage_items(base_id) when is_binary(base_id) do
    Repo.all(
      from storage_item in StorageItem,
        where: storage_item.base_id == ^base_id,
        order_by: [asc: storage_item.inserted_at],
        preload: [:item_template]
    )
  end

  def get_storage_item!(id) do
    StorageItem
    |> Repo.get!(id)
    |> Repo.preload(:item_template)
  end

  def active_base_at_location(character_id, location_id)
      when is_binary(character_id) and is_binary(location_id) do
    Repo.get_by(Base,
      owner_character_id: character_id,
      location_id: location_id,
      status: :active
    )
  end

  def building_bases(character_id) when is_binary(character_id) do
    Repo.all(
      from base in Base,
        where: base.owner_character_id == ^character_id and base.status == :building,
        order_by: [asc: base.inserted_at],
        preload: [:location]
    )
  end

  def purchase_city_base(%Character{} = character, %Location{} = location, attrs \\ %{}) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      character = lock_character!(character.id)
      location = Repo.get!(Location, location.id)
      validate_city_purchase!(character, location)

      %Base{}
      |> Base.changeset(%{
        owner_character_id: character.id,
        realm_id: character.realm_id,
        location_id: location.id,
        name: attrs["name"] || "#{location.name} Base",
        kind: :city_purchase,
        status: :active,
        storage_weight_capacity: attrs["storage_weight_capacity"] || @city_storage_capacity,
        metadata: attrs["metadata"] || %{},
        built_at: DateTime.utc_now()
      })
      |> Repo.insert!()
      |> Repo.preload(:location)
    end)
    |> normalize_transaction_result()
  end

  def start_custom_base_build(
        %Character{} = character,
        %Location{} = location,
        attrs \\ %{},
        opts \\ []
      ) do
    attrs = stringify_keys(attrs)
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())
    build_days = Keyword.get(opts, :build_days, 28)

    Repo.transaction(fn ->
      character = lock_character!(character.id)
      location = Repo.get!(Location, location.id)
      validate_custom_build!(character, location)

      ready_at = Clock.arrival_at(started_at, build_days)

      base =
        %Base{}
        |> Base.changeset(%{
          owner_character_id: character.id,
          realm_id: character.realm_id,
          location_id: location.id,
          name: attrs["name"] || "#{location.name} Outpost",
          kind: :custom_build,
          status: :building,
          storage_weight_capacity: attrs["storage_weight_capacity"] || @custom_storage_capacity,
          metadata: Map.put(attrs["metadata"] || %{}, "build_days", build_days),
          build_started_at: started_at,
          ready_at: ready_at
        })
        |> Repo.insert!()

      job =
        %{"base_id" => base.id}
        |> CompleteBaseBuildWorker.new(
          schedule_in: max(DateTime.diff(ready_at, DateTime.utc_now(), :second), 0)
        )
        |> Oban.insert!()

      %{base: Repo.preload(base, :location), worker_job: job}
    end)
    |> normalize_transaction_result()
  end

  def complete_base_build_by_id(base_id, opts \\ []) when is_binary(base_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force, false)

    Repo.transaction(fn ->
      base = lock_base!(base_id)
      character = lock_character!(base.owner_character_id)

      cond do
        base.status != :building ->
          Repo.rollback(base_changeset("base is not under construction"))

        not force? and DateTime.compare(now, base.ready_at) == :lt ->
          Repo.rollback(base_changeset("base build is not due yet"))

        true ->
          updated_base =
            base
            |> Base.changeset(%{status: :active, built_at: now})
            |> Repo.update!()

          _ = Notifications.notify_base_ready(character, updated_base)

          Repo.preload(updated_base, :location)
      end
    end)
    |> normalize_transaction_result()
  end

  def complete_due_base_builds(now \\ DateTime.utc_now()) do
    Base
    |> where([base], base.status == :building and base.ready_at <= ^now)
    |> Repo.all()
    |> Enum.map(fn base -> complete_base_build_by_id(base.id, now: now, force: true) end)
  end

  def storage_weight(%Base{} = base) do
    base.id
    |> list_storage_items()
    |> Enum.reduce(0, fn storage_item, total ->
      total + storage_item.quantity * storage_item.item_template.weight
    end)
  end

  def available_storage_capacity(%Base{} = base) do
    max(base.storage_weight_capacity - storage_weight(base), 0)
  end

  def deposit_item(
        %Character{} = character,
        %Base{} = base,
        %InventoryItem{} = inventory_item,
        quantity \\ 1
      )
      when is_integer(quantity) do
    Repo.transaction(fn ->
      character = lock_character!(character.id)
      base = lock_base!(base.id)
      inventory_item = lock_inventory_item!(inventory_item.id)

      validate_base_transfer!(character, base, quantity)
      validate_inventory_deposit!(character, inventory_item, quantity)
      validate_storage_capacity!(base, inventory_item.item_template, quantity)

      storage_item = transfer_to_storage!(base, inventory_item, quantity)

      %{
        base: Repo.preload(base, :location),
        storage_item: Repo.preload(storage_item, :item_template)
      }
    end)
    |> normalize_transaction_result()
  end

  def withdraw_item(
        %Character{} = character,
        %Base{} = base,
        %StorageItem{} = storage_item,
        quantity \\ 1
      )
      when is_integer(quantity) do
    Repo.transaction(fn ->
      character = lock_character!(character.id)
      base = lock_base!(base.id)
      storage_item = lock_storage_item!(storage_item.id)

      validate_base_transfer!(character, base, quantity)
      validate_storage_withdrawal!(base, storage_item, quantity)

      inventory_item = transfer_from_storage!(character, storage_item, quantity)

      %{
        base: Repo.preload(base, :location),
        inventory_item: Repo.preload(inventory_item, :item_template)
      }
    end)
    |> normalize_transaction_result()
  end

  defp validate_city_purchase!(%Character{} = character, %Location{} = location) do
    cond do
      character.realm_id != location.realm_id ->
        Repo.rollback(base_changeset("location must belong to the same realm"))

      location.kind != :city ->
        Repo.rollback(base_changeset("city bases can only be purchased in cities"))

      active_base_at_location(character.id, location.id) ->
        Repo.rollback(base_changeset("character already owns an active base at this location"))

      true ->
        :ok
    end
  end

  defp validate_custom_build!(%Character{} = character, %Location{} = location) do
    cond do
      character.realm_id != location.realm_id ->
        Repo.rollback(base_changeset("location must belong to the same realm"))

      location.kind == :city ->
        Repo.rollback(
          base_changeset("city locations use purchase flow instead of custom building")
        )

      active_base_at_location(character.id, location.id) ->
        Repo.rollback(base_changeset("character already owns an active base at this location"))

      true ->
        :ok
    end
  end

  defp validate_base_transfer!(%Character{} = character, %Base{} = base, quantity) do
    cond do
      quantity <= 0 ->
        Repo.rollback(base_changeset("quantity must be greater than zero"))

      base.owner_character_id != character.id ->
        Repo.rollback(base_changeset("base does not belong to this character"))

      base.status != :active ->
        Repo.rollback(base_changeset("base is not active"))

      character.current_location_id != base.location_id ->
        Repo.rollback(base_changeset("character must be at the base location"))

      true ->
        :ok
    end
  end

  defp validate_inventory_deposit!(
         %Character{} = character,
         %InventoryItem{} = inventory_item,
         quantity
       ) do
    cond do
      inventory_item.character_id != character.id ->
        Repo.rollback(base_changeset("inventory item does not belong to this character"))

      quantity > Inventory.available_quantity(inventory_item) ->
        Repo.rollback(base_changeset("quantity exceeds the available inventory"))

      inventory_item.item_template.stackable == false and quantity != 1 ->
        Repo.rollback(base_changeset("non-stackable items must be deposited one at a time"))

      true ->
        :ok
    end
  end

  defp validate_storage_capacity!(%Base{} = base, item_template, quantity) do
    required_weight = item_template.weight * quantity

    if storage_weight(base) + required_weight > base.storage_weight_capacity do
      Repo.rollback(base_changeset("base storage capacity would be exceeded"))
    else
      :ok
    end
  end

  defp validate_storage_withdrawal!(%Base{} = base, %StorageItem{} = storage_item, quantity) do
    cond do
      storage_item.base_id != base.id ->
        Repo.rollback(base_changeset("storage item does not belong to this base"))

      quantity > storage_item.quantity ->
        Repo.rollback(base_changeset("quantity exceeds the stored amount"))

      storage_item.item_template.stackable == false and quantity != 1 ->
        Repo.rollback(base_changeset("non-stackable items must be withdrawn one at a time"))

      true ->
        :ok
    end
  end

  defp transfer_to_storage!(%Base{} = base, %InventoryItem{} = inventory_item, quantity) do
    item_template = Repo.preload(inventory_item, :item_template).item_template
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

    if item_template.stackable do
      case Repo.get_by(StorageItem, base_id: base.id, item_template_id: item_template.id) do
        %StorageItem{} = existing_storage_item ->
          existing_storage_item
          |> StorageItem.changeset(%{quantity: existing_storage_item.quantity + quantity})
          |> Repo.update!()

        nil ->
          %StorageItem{}
          |> StorageItem.changeset(%{
            base_id: base.id,
            item_template_id: item_template.id,
            quantity: quantity,
            durability: 0,
            metadata: inventory_item.metadata || %{}
          })
          |> Repo.insert!()
      end
    else
      %StorageItem{}
      |> StorageItem.changeset(%{
        base_id: base.id,
        item_template_id: item_template.id,
        quantity: 1,
        durability: inventory_item.durability,
        metadata: inventory_item.metadata || %{}
      })
      |> Repo.insert!()
    end
  end

  defp transfer_from_storage!(%Character{} = character, %StorageItem{} = storage_item, quantity) do
    item_template = Repo.preload(storage_item, :item_template).item_template
    remaining_quantity = storage_item.quantity - quantity

    if remaining_quantity == 0 do
      Repo.delete!(storage_item)
    else
      storage_item
      |> StorageItem.changeset(%{quantity: remaining_quantity})
      |> Repo.update!()
    end

    {:ok, inventory_item} =
      Inventory.grant_item(character, item_template, %{
        quantity: quantity,
        durability: storage_item.durability,
        metadata: storage_item.metadata || %{}
      })

    inventory_item
  end

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_base!(base_id) do
    Base
    |> where([base], base.id == ^base_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload(:location)
  end

  defp lock_inventory_item!(inventory_item_id) do
    InventoryItem
    |> where([item], item.id == ^inventory_item_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload(:item_template)
  end

  defp lock_storage_item!(storage_item_id) do
    StorageItem
    |> where([storage_item], storage_item.id == ^storage_item_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload(:item_template)
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp base_changeset(message) do
    %Base{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
