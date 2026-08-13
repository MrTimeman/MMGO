defmodule MMGO.Grimoires do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Economy
  alias MMGO.Grimoires.{Grimoire, GrimoireEntry}
  alias MMGO.Repo
  alias MMGO.Spells.Spell
  alias MMGO.Worlds.Realm

  @purchase_tiers [
    %{
      key: "pocket",
      name: "Карманный гримуар",
      capacity: 3,
      weight: 1,
      price: 40
    },
    %{
      key: "traveler",
      name: "Дорожный гримуар",
      capacity: 5,
      weight: 2,
      price: 120
    },
    %{
      key: "scholar",
      name: "Учёный гримуар",
      capacity: 8,
      weight: 4,
      price: 350
    },
    %{
      key: "archivist",
      name: "Архивный гримуар",
      capacity: 12,
      weight: 8,
      price: 900
    }
  ]

  @doc "Returns the fixed, realm-currency grimoire catalog."
  def purchase_tiers, do: @purchase_tiers

  def list_grimoires_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from grimoire in Grimoire,
        where: grimoire.owner_character_id == ^character_id,
        order_by: [asc: grimoire.inserted_at],
        preload: [entries: :spell]
    )
  end

  def get_grimoire!(id) do
    Grimoire
    |> Repo.get!(id)
    |> Repo.preload(entries: :spell)
  end

  def active_grimoire_for_character(character_id) when is_binary(character_id) do
    Repo.get_by(Grimoire, owner_character_id: character_id, status: :active)
  end

  def spell_inscribed?(grimoire_id, spell_id)
      when is_binary(grimoire_id) and is_binary(spell_id) do
    Repo.exists?(
      from entry in GrimoireEntry,
        where: entry.grimoire_id == ^grimoire_id and entry.spell_id == ^spell_id
    )
  end

  def create_grimoire(%Character{} = character, attrs \\ %{}) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("owner_character_id", character.id)
      |> Map.put("realm_id", character.realm_id)

    %Grimoire{}
    |> Grimoire.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Purchases one immutable-capacity grimoire and settles its price to the realm treasury."
  def purchase_grimoire(character, tier_key, attrs \\ %{})

  def purchase_grimoire(%Character{} = character, tier_key, attrs) when is_map(attrs) do
    case purchase_tier(tier_key) do
      nil ->
        {:error, purchase_changeset("grimoire tier is invalid")}

      tier ->
        attrs = stringify_keys(attrs)

        Repo.transaction(fn ->
          character = lock_character!(character.id)
          realm = Repo.get!(Realm, character.realm_id)

          with {:ok, buyer_account} <- Economy.ensure_character_account(character),
               {:ok, treasury_account} <- Economy.ensure_treasury_account(realm),
               {:ok, payment} <-
                 Economy.transfer(buyer_account, treasury_account, tier.price, %{
                   entry_type: "purchase",
                   source: "grimoire_purchase",
                   grimoire_tier: tier.key,
                   grimoire_price: tier.price,
                   character_id: character.id
                 }) do
            grimoire =
              %Grimoire{}
              |> Grimoire.changeset(%{
                name: Map.get(attrs, "name", tier.name),
                capacity: tier.capacity,
                weight: tier.weight,
                owner_character_id: character.id,
                realm_id: character.realm_id,
                metadata: %{
                  "purchase_tier" => tier.key,
                  "purchase_price" => tier.price,
                  "purchase_source" => "realm_grimoire_catalog"
                }
              })
              |> Repo.insert!()

            %{grimoire: grimoire, payment: payment, tier: tier}
          else
            {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
          end
        end)
        |> normalize_transaction_result()
    end
  end

  def purchase_grimoire(_character, _tier_key, _attrs),
    do: {:error, purchase_changeset("grimoire tier is invalid")}

  def inscribe_spell(%Grimoire{} = grimoire, %Spell{} = spell, attrs \\ %{}) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      grimoire = lock_grimoire!(grimoire.id)
      spell = Repo.get!(Spell, spell.id)

      with :ok <- validate_grimoire_owner(grimoire, spell),
           :ok <- validate_grimoire_is_writable(grimoire),
           :ok <- validate_grimoire_capacity(grimoire),
           :ok <- validate_duplicate_spell(grimoire, spell) do
        slot_index = attrs["slot_index"] || next_slot_index(grimoire)

        %GrimoireEntry{}
        |> GrimoireEntry.changeset(%{
          grimoire_id: grimoire.id,
          spell_id: spell.id,
          slot_index: slot_index
        })
        |> Repo.insert!()
      else
        {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  @doc """
  Renames one grimoire.

  A book's name is a label its owner chooses, not part of its magic, so this
  stays open even after the binding is sealed: a shelf is only navigable when
  the spines can be told apart.
  """
  def rename_grimoire(%Grimoire{} = grimoire, name) when is_binary(name) do
    grimoire
    |> Changeset.change()
    |> Changeset.cast(%{"name" => String.trim(name)}, [:name])
    |> Changeset.validate_required([:name])
    |> Changeset.validate_length(:name, min: 1, max: 60)
    |> Repo.update()
  end

  def rename_grimoire(%Grimoire{}, _name), do: {:error, invalid_name_changeset()}

  @doc """
  Removes one spell from a grimoire that still accepts changes.

  Swapping a formula out matters most in the arena, where the book is small and
  the point is to keep trying combinations; a sealed world book stays closed.
  The spell itself is untouched and can be inscribed again later.
  """
  def erase_spell(%Grimoire{} = grimoire, %Spell{} = spell) do
    Repo.transaction(fn ->
      grimoire = lock_grimoire!(grimoire.id)

      with :ok <- validate_grimoire_is_writable(grimoire),
           %GrimoireEntry{} = entry <-
             Repo.get_by(GrimoireEntry, grimoire_id: grimoire.id, spell_id: spell.id) do
        Repo.delete!(entry)
      else
        nil -> Repo.rollback(missing_entry_changeset())
        {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def activate_grimoire(%Character{} = character, %Grimoire{} = grimoire) do
    Repo.transaction(fn ->
      grimoire = lock_owned_grimoire(character.id, grimoire.id)

      with %Grimoire{} = grimoire <- grimoire,
           :ok <- validate_active_owner(character, grimoire),
           :ok <- validate_activation_ready(grimoire) do
        seal_previous =
          Repo.update_all(
            from(existing in Grimoire,
              where:
                existing.owner_character_id == ^character.id and existing.status == :active and
                  existing.id != ^grimoire.id
            ),
            set: [status: :sealed]
          )

        active_grimoire =
          grimoire
          |> Grimoire.changeset(%{status: :active})
          |> Repo.update!()
          |> Repo.preload(entries: :spell)

        %{seal_previous: seal_previous, activate_grimoire: active_grimoire}
      else
        nil -> Repo.rollback(ownership_changeset())
        {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def resolve_selected_grimoire(character_id, nil) when is_binary(character_id) do
    {:ok, active_grimoire_for_character(character_id)}
  end

  def resolve_selected_grimoire(character_id, grimoire_id)
      when is_binary(character_id) and is_binary(grimoire_id) do
    case Repo.get_by(Grimoire, id: grimoire_id, owner_character_id: character_id) do
      %Grimoire{} = grimoire -> {:ok, grimoire}
      nil -> {:error, selected_grimoire_changeset()}
    end
  end

  def resolve_selected_grimoire(_character_id, nil), do: {:ok, nil}

  def resolve_selected_grimoire(_character_id, _grimoire_id),
    do: {:error, selected_grimoire_changeset()}

  def change_grimoire(%Grimoire{} = grimoire, attrs \\ %{}) do
    Grimoire.changeset(grimoire, attrs)
  end

  defp validate_grimoire_owner(%Grimoire{} = grimoire, %Spell{} = spell) do
    cond do
      grimoire.owner_character_id != spell.creator_character_id ->
        {:error, ownership_changeset()}

      grimoire.realm_id != spell.realm_id ->
        {:error, ownership_changeset("spell must belong to the same realm")}

      true ->
        :ok
    end
  end

  @doc """
  Whether a grimoire still accepts changes.

  A world grimoire is a physical book: sealing it, or carrying it into the
  world, closes it to its owner. An arena loadout is not a book but a deck —
  free, weightless, and meant to be rearranged between fights — so it stays open
  while it is the active one.

  Both the domain guard and the screen ask this same question. They used to
  decide separately, which is how an arena player ended up with a book the
  server would refuse and a screen that quietly hid the form rather than saying
  so.
  """
  def writable?(%Grimoire{} = grimoire), do: grimoire.status == :draft or arena?(grimoire)
  def writable?(_grimoire), do: false

  @doc "Whether this grimoire is an arena loadout rather than a world book."
  def arena?(%Grimoire{metadata: metadata}) when is_map(metadata),
    do: Map.get(metadata, "arena") == true

  def arena?(_grimoire), do: false

  defp validate_grimoire_is_writable(%Grimoire{} = grimoire) do
    if writable?(grimoire), do: :ok, else: {:error, writable_changeset()}
  end

  defp validate_grimoire_is_writable(_grimoire), do: {:error, writable_changeset()}

  defp validate_grimoire_capacity(%Grimoire{} = grimoire) do
    if length(grimoire.entries) >= grimoire.capacity do
      {:error, capacity_changeset()}
    else
      :ok
    end
  end

  defp validate_duplicate_spell(%Grimoire{} = grimoire, %Spell{} = spell) do
    if Enum.any?(grimoire.entries, &(&1.spell_id == spell.id)) do
      {:error, duplicate_spell_changeset()}
    else
      :ok
    end
  end

  defp validate_active_owner(%Character{} = character, %Grimoire{} = grimoire) do
    if grimoire.owner_character_id == character.id do
      :ok
    else
      {:error, ownership_changeset()}
    end
  end

  defp validate_activation_ready(%Grimoire{} = grimoire) do
    cond do
      grimoire.status == :active -> :ok
      Enum.empty?(grimoire.entries) -> {:error, empty_grimoire_changeset()}
      true -> :ok
    end
  end

  defp next_slot_index(%Grimoire{} = grimoire) do
    grimoire.entries
    |> Enum.map(& &1.slot_index)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp lock_grimoire!(grimoire_id) do
    Grimoire
    |> where([grimoire], grimoire.id == ^grimoire_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload(entries: :spell)
  end

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_owned_grimoire(character_id, grimoire_id) do
    Grimoire
    |> where([grimoire], grimoire.owner_character_id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.all()
    |> Enum.find(&(&1.id == grimoire_id))
    |> case do
      nil -> nil
      grimoire -> Repo.preload(grimoire, entries: :spell)
    end
  end

  defp ownership_changeset(message \\ "grimoire must belong to the same character") do
    %Grimoire{}
    |> Changeset.change()
    |> Changeset.add_error(:owner_character_id, message)
  end

  defp writable_changeset do
    %Grimoire{}
    |> Changeset.change()
    |> Changeset.add_error(:status, "sealed grimoires cannot be modified")
  end

  defp capacity_changeset do
    %Grimoire{}
    |> Changeset.change()
    |> Changeset.add_error(:capacity, "grimoire is at capacity")
  end

  defp invalid_name_changeset do
    %Grimoire{}
    |> Changeset.change()
    |> Changeset.add_error(:name, "grimoire name is invalid")
  end

  defp missing_entry_changeset do
    %Grimoire{}
    |> Changeset.change()
    |> Changeset.add_error(:entries, "spell is not inscribed in this grimoire")
  end

  defp duplicate_spell_changeset do
    %Grimoire{}
    |> Changeset.change()
    |> Changeset.add_error(:entries, "spell is already inscribed")
  end

  defp empty_grimoire_changeset do
    %Grimoire{}
    |> Changeset.change()
    |> Changeset.add_error(:entries, "grimoire must contain at least one spell before activation")
  end

  defp selected_grimoire_changeset do
    %Grimoire{}
    |> Changeset.change()
    |> Changeset.add_error(:id, "selected grimoire is invalid for this character")
  end

  defp purchase_changeset(message) do
    %Grimoire{}
    |> Changeset.change()
    |> Changeset.add_error(:metadata, message)
  end

  defp purchase_tier(tier_key) when is_binary(tier_key),
    do: Enum.find(@purchase_tiers, &(&1.key == tier_key))

  defp purchase_tier(tier_key) when is_atom(tier_key), do: purchase_tier(Atom.to_string(tier_key))
  defp purchase_tier(_tier_key), do: nil

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}
end
