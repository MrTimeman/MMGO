defmodule MMGO.Bases do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Bases.{Base, CompleteBaseBuildWorker, Ownership, StorageItem}
  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Inventory.{InventoryItem, ItemTemplate}
  alias MMGO.Notifications
  alias MMGO.Organizations.{Membership, Organization, Role}
  alias MMGO.Repo
  alias MMGO.Survival
  alias MMGO.Travel.Clock
  alias MMGO.Worlds
  alias MMGO.Worlds.Location

  @city_storage_capacity 250
  @custom_storage_capacity 350
  @default_city_purchase_price 500
  @default_custom_build_price 250
  @default_custom_build_days 28
  @default_build_materials %{"construction_material" => 5}

  @doc "Returns server-owned price, tax, material, and timing terms for acquiring a base."
  def acquisition_quote(%Character{} = character, %Location{} = location) do
    if character.realm_id == location.realm_id do
      ruleset = Worlds.realm_ruleset(character.realm_id)
      tax_rate_bps = ruleset["legal_market_tax_rate_bps"]

      case location.kind do
        :city ->
          subtotal =
            positive_metadata_integer(
              location,
              "base_purchase_price",
              @default_city_purchase_price
            )

          tax_amount = div(subtotal * tax_rate_bps, 10_000)

          {:ok,
           %{
             kind: :city_purchase,
             subtotal: subtotal,
             tax_rate_bps: tax_rate_bps,
             tax_amount: tax_amount,
             total_coin_cost: subtotal + tax_amount,
             build_days: 0,
             materials: []
           }}

        _other ->
          subtotal =
            positive_metadata_integer(location, "base_build_price", @default_custom_build_price)

          tax_amount = div(subtotal * tax_rate_bps, 10_000)

          {:ok,
           %{
             kind: :custom_build,
             subtotal: subtotal,
             tax_rate_bps: tax_rate_bps,
             tax_amount: tax_amount,
             total_coin_cost: subtotal + tax_amount,
             build_days:
               positive_metadata_integer(
                 location,
                 "base_build_game_days",
                 @default_custom_build_days
               ),
             materials: build_material_requirements(location)
           }}
      end
    else
      {:error, base_changeset("location must belong to the same realm")}
    end
  end

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

  @doc "Lists the direct and organization-custodied bases available to one character."
  def list_accessible_bases_for_character(%Character{} = character) do
    direct_bases = list_bases_for_character(character.id)

    shared_bases =
      Base
      |> where([base], base.realm_id == ^character.realm_id and base.status != :abandoned)
      |> order_by([base], asc: base.inserted_at)
      |> preload([:location])
      |> Repo.all()
      |> Enum.reject(&(&1.owner_character_id == character.id))
      |> Enum.filter(&Ownership.accessible?(&1, character))

    (direct_bases ++ shared_bases)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.inserted_at)
  end

  @doc "Lists every active base at this location that the character can actually use."
  def accessible_active_bases_at_location(%Character{} = character, location_id)
      when is_binary(location_id) do
    Base
    |> where(
      [base],
      base.realm_id == ^character.realm_id and base.location_id == ^location_id and
        base.status == :active
    )
    |> order_by([base], asc: base.inserted_at)
    |> preload([:location])
    |> Repo.all()
    |> Enum.filter(&Ownership.accessible?(&1, character))
    |> Enum.sort_by(fn base -> if(base.owner_character_id == character.id, do: 0, else: 1) end)
  end

  def accessible_active_bases_at_location(_character, _location_id), do: []

  @doc "Finds one explicitly selected, accessible active base at the current location."
  def accessible_active_base_at_location(%Character{} = character, location_id, base_id)
      when is_binary(location_id) and is_binary(base_id) do
    character
    |> accessible_active_bases_at_location(location_id)
    |> Enum.find(&(&1.id == base_id))
  end

  def accessible_active_base_at_location(_character, _location_id, _base_id), do: nil

  @doc "Checks direct ownership or live organization custody for an already-loaded base."
  def can_access?(%Base{} = base, %Character{} = character),
    do: Ownership.accessible?(base, character)

  def can_access?(_base, _character), do: false

  @doc "Returns a base's real share record for presentation through a scoped facade."
  def ownership_state(%Base{} = base), do: Ownership.ownership_state(base)

  @doc "Changes an organization share only when the primary owner is a live treasury custodian."
  def configure_organization_share(
        %Base{} = base,
        %Character{} = actor,
        %Organization{} = organization,
        share_bps
      )
      when is_integer(share_bps) and share_bps in 0..9_999 do
    Repo.transaction(fn ->
      actor = lock_character!(actor.id)
      base = lock_base!(base.id)
      organization = lock_organization!(organization.id)

      validate_base_owner!(base, actor)
      validate_base_ready_for_ownership_change!(base, actor)
      validate_organization_realm!(base, organization, share_bps)

      if share_bps > 0 do
        validate_organization_custodian!(organization, actor)
      end

      case Ownership.put_organization_share(base, organization.id, share_bps) do
        {:ok, metadata} ->
          base
          |> Base.changeset(%{metadata: metadata})
          |> Repo.update!()
          |> Repo.preload(:location)

        {:error, :ownership_shares_exceed_cap} ->
          Repo.rollback(base_changeset("organization shares must leave a title-holder share"))

        {:error, :invalid_ownership_share} ->
          Repo.rollback(base_changeset("organization ownership share is invalid"))
      end
    end)
    |> normalize_transaction_result()
  end

  def configure_organization_share(_base, _actor, _organization, _share_bps),
    do: {:error, base_changeset("organization ownership share is invalid")}

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
      {:ok, quote} = acquisition_quote(character, location)
      charge_acquisition!(character, location, quote)

      %Base{}
      |> Base.changeset(%{
        owner_character_id: character.id,
        realm_id: character.realm_id,
        location_id: location.id,
        name: attrs["name"] || "#{location.name} Base",
        kind: :city_purchase,
        status: :active,
        storage_weight_capacity: attrs["storage_weight_capacity"] || @city_storage_capacity,
        metadata: acquisition_metadata(attrs["metadata"], quote),
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

    Repo.transaction(fn ->
      character = lock_character!(character.id)
      location = Repo.get!(Location, location.id)
      validate_custom_build!(character, location)
      {:ok, quoted_terms} = acquisition_quote(character, location)

      quote =
        case Keyword.fetch(opts, :build_days) do
          {:ok, build_days} when is_integer(build_days) and build_days > 0 ->
            Map.put(quoted_terms, :build_days, build_days)

          _other ->
            quoted_terms
        end

      charge_acquisition!(character, location, quote)
      consume_build_materials!(character, quote.materials)

      ready_at = Clock.arrival_at(started_at, quote.build_days)

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
          metadata: acquisition_metadata(attrs["metadata"], quote),
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

  @doc """
  Lets a character recover from persistent hunger at their own active base.

  One real ration from protected storage is consumed inside the same
  transaction as the recovery. This keeps a base rest useful without letting a
  browser claim recovery, a foreign base, or an unlimited food source.
  """
  def rest_at_base(%Character{} = character, %Base{} = base) do
    Repo.transaction(fn ->
      character = lock_character!(character.id)
      base = lock_base!(base.id)

      validate_base_rest!(character, base)

      survival = Survival.summary(character)

      if survival.starving? or survival.health_drain > 0 do
        case lock_rest_food(base.id) do
          %StorageItem{} = food ->
            consume_storage_food!(food)

            case Survival.recover_after_food(Repo, character) do
              {:ok, recovered_character} ->
                %{
                  character: recovered_character,
                  food_units_consumed: food.item_template.nutrition_units,
                  item_template: food.item_template
                }

              {:error, %Changeset{} = changeset} ->
                Repo.rollback(changeset)
            end

          nil ->
            Repo.rollback(base_changeset("stored provisions are required to rest"))
        end
      else
        Repo.rollback(base_changeset("character has no hunger consequences to recover"))
      end
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

      not Ownership.accessible_for_update?(base, character) ->
        Repo.rollback(base_changeset("base does not grant this character custody access"))

      base.status != :active ->
        Repo.rollback(base_changeset("base is not active"))

      character.current_location_id != base.location_id ->
        Repo.rollback(base_changeset("character must be at the base location"))

      true ->
        :ok
    end
  end

  defp validate_base_rest!(%Character{} = character, %Base{} = base) do
    cond do
      not Ownership.accessible_for_update?(base, character) ->
        Repo.rollback(base_changeset("base does not grant this character custody access"))

      base.status != :active ->
        Repo.rollback(base_changeset("base is not active"))

      character.current_location_id != base.location_id ->
        Repo.rollback(base_changeset("character must be at the base location"))

      true ->
        :ok
    end
  end

  defp lock_rest_food(base_id) do
    StorageItem
    |> where([storage_item], storage_item.base_id == ^base_id and storage_item.quantity > 0)
    |> join(:inner, [storage_item], template in assoc(storage_item, :item_template))
    |> where(
      [_storage_item, template],
      template.item_type == :food and template.nutrition_units > 0
    )
    |> order_by([storage_item, _template], asc: storage_item.inserted_at)
    |> limit(1)
    |> lock("FOR UPDATE")
    |> preload(:item_template)
    |> Repo.one()
  end

  defp consume_storage_food!(%StorageItem{quantity: 1} = storage_item),
    do: Repo.delete!(storage_item)

  defp consume_storage_food!(%StorageItem{} = storage_item) do
    storage_item
    |> StorageItem.changeset(%{quantity: storage_item.quantity - 1})
    |> Repo.update!()
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

  defp charge_acquisition!(%Character{} = character, %Location{} = location, quote) do
    {:ok, payer_account} = Economy.ensure_character_account(character)
    treasury_account = Economy.treasury_account_for_realm(character.realm_id)

    if is_nil(treasury_account) do
      Repo.rollback(base_changeset("realm treasury is unavailable"))
    end

    case Economy.transfer(payer_account, treasury_account, quote.total_coin_cost, %{
           entry_type: "tax",
           source: "base_acquisition",
           location_id: location.id,
           acquisition_kind: to_string(quote.kind),
           subtotal: quote.subtotal,
           tax_rate_bps: quote.tax_rate_bps,
           tax_amount: quote.tax_amount
         }) do
      {:ok, _result} -> :ok
      {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
    end
  end

  defp consume_build_materials!(%Character{} = character, requirements) do
    Enum.each(requirements, fn %{code: code, quantity: quantity} ->
      items =
        InventoryItem
        |> join(:inner, [item], template in ItemTemplate,
          on: template.id == item.item_template_id
        )
        |> where(
          [item, template],
          item.character_id == ^character.id and template.code == ^code and
            item.quantity - item.reserved_quantity > 0
        )
        |> order_by([item, _template], asc: item.inserted_at)
        |> lock("FOR UPDATE OF i0")
        |> Repo.all()

      {remaining, _items} =
        Enum.reduce_while(items, {quantity, []}, fn item, {remaining, consumed} ->
          if remaining <= 0 do
            {:halt, {remaining, consumed}}
          else
            taken = min(Inventory.available_quantity(item), remaining)
            next_quantity = item.quantity - taken

            if next_quantity == 0 do
              Repo.delete!(item)
            else
              item
              |> InventoryItem.changeset(%{
                quantity: next_quantity,
                reserved_quantity: item.reserved_quantity
              })
              |> Repo.update!()
            end

            {:cont, {remaining - taken, [item.id | consumed]}}
          end
        end)

      if remaining > 0 do
        Repo.rollback(base_changeset("missing construction material #{code}"))
      end
    end)
  end

  defp acquisition_metadata(metadata, quote) do
    metadata = if is_map(metadata), do: stringify_keys(metadata), else: %{}

    Map.put(metadata, "acquisition", %{
      "subtotal" => quote.subtotal,
      "tax_rate_bps" => quote.tax_rate_bps,
      "tax_amount" => quote.tax_amount,
      "total_coin_cost" => quote.total_coin_cost,
      "build_days" => quote.build_days,
      "materials" =>
        Enum.map(quote.materials, fn material ->
          %{"code" => material.code, "quantity" => material.quantity}
        end)
    })
  end

  defp build_material_requirements(%Location{} = location) do
    case Map.get(location.metadata || %{}, "base_build_materials") do
      requirements when is_map(requirements) ->
        requirements
        |> Enum.flat_map(fn
          {code, quantity} when is_binary(code) and is_integer(quantity) and quantity > 0 ->
            [%{code: code, quantity: quantity}]

          _invalid ->
            []
        end)
        |> case do
          [] -> default_build_material_requirements()
          normalized -> Enum.sort_by(normalized, & &1.code)
        end

      _other ->
        default_build_material_requirements()
    end
  end

  defp default_build_material_requirements do
    Enum.map(@default_build_materials, fn {code, quantity} ->
      %{code: code, quantity: quantity}
    end)
  end

  defp positive_metadata_integer(%Location{} = location, key, default) do
    case Map.get(location.metadata || %{}, key) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
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

  defp lock_organization!(organization_id) do
    Organization
    |> where([organization], organization.id == ^organization_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp validate_base_owner!(%Base{} = base, %Character{} = actor) do
    if base.owner_character_id == actor.id do
      :ok
    else
      Repo.rollback(base_changeset("only the base owner can change organization shares"))
    end
  end

  defp validate_base_ready_for_ownership_change!(%Base{} = base, %Character{} = actor) do
    cond do
      base.status != :active ->
        Repo.rollback(base_changeset("only active bases can grant organization custody"))

      actor.current_location_id != base.location_id ->
        Repo.rollback(base_changeset("base owner must be present at the base location"))

      true ->
        :ok
    end
  end

  defp validate_organization_realm!(%Base{} = base, %Organization{} = organization, share_bps) do
    cond do
      organization.realm_id != base.realm_id ->
        Repo.rollback(base_changeset("organization must belong to the base realm"))

      share_bps > 0 and organization.status != :active ->
        Repo.rollback(base_changeset("organization is not active"))

      true ->
        :ok
    end
  end

  defp validate_organization_custodian!(%Organization{} = organization, %Character{} = actor) do
    membership =
      Membership
      |> where(
        [membership],
        membership.organization_id == ^organization.id and membership.character_id == ^actor.id and
          membership.status == :active
      )
      |> lock("FOR UPDATE")
      |> Repo.one()

    case membership do
      nil ->
        Repo.rollback(base_changeset("base owner is not an active organization member"))

      membership ->
        role =
          Role
          |> where(
            [role],
            role.id == ^membership.role_id and role.organization_id == ^organization.id
          )
          |> lock("FOR UPDATE")
          |> Repo.one()

        if role && "manage_treasury" in role.permissions do
          :ok
        else
          Repo.rollback(base_changeset("organization role lacks treasury custody authority"))
        end
    end
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
