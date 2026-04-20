defmodule MMGO.Grimoires do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Ecto.Multi
  alias MMGO.Accounts.Character
  alias MMGO.Grimoires.{Grimoire, GrimoireEntry}
  alias MMGO.Repo
  alias MMGO.Spells.Spell

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

  def inscribe_spell(%Grimoire{} = grimoire, %Spell{} = spell, attrs \\ %{}) do
    grimoire = get_grimoire!(grimoire.id)
    attrs = stringify_keys(attrs)

    with :ok <- validate_grimoire_owner(grimoire, spell),
         :ok <- validate_grimoire_is_writable(grimoire),
         :ok <- validate_grimoire_capacity(grimoire),
         :ok <- validate_duplicate_spell(grimoire, spell) do
      slot_index = attrs["slot_index"] || next_slot_index(grimoire)

      %GrimoireEntry{inscribed_at: DateTime.utc_now()}
      |> GrimoireEntry.changeset(%{
        grimoire_id: grimoire.id,
        spell_id: spell.id,
        slot_index: slot_index
      })
      |> Repo.insert()
    end
  end

  def activate_grimoire(%Character{} = character, %Grimoire{} = grimoire) do
    grimoire = get_grimoire!(grimoire.id)

    with :ok <- validate_active_owner(character, grimoire),
         :ok <- validate_activation_ready(grimoire) do
      Multi.new()
      |> Multi.update_all(
        :seal_previous,
        from(existing in Grimoire,
          where:
            existing.owner_character_id == ^character.id and existing.status == :active and
              existing.id != ^grimoire.id
        ),
        set: [status: :sealed]
      )
      |> Multi.update(:activate_grimoire, Grimoire.changeset(grimoire, %{status: :active}))
      |> Repo.transaction()
    end
  end

  def resolve_selected_grimoire(character_id, nil) when is_binary(character_id) do
    {:ok, active_grimoire_for_character(character_id)}
  end

  def resolve_selected_grimoire(character_id, grimoire_id)
      when is_binary(character_id) and is_binary(grimoire_id) do
    case Repo.get_by(Grimoire, id: grimoire_id, owner_character_id: character_id) do
      %Grimoire{status: :draft} ->
        {:error, selected_grimoire_changeset("selected grimoire must be sealed or active")}

      %Grimoire{} = grimoire ->
        {:ok, grimoire}

      nil ->
        {:error, selected_grimoire_changeset()}
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

  defp validate_grimoire_is_writable(%Grimoire{status: status})
       when status in [:sealed, :active] do
    {:error, writable_changeset()}
  end

  defp validate_grimoire_is_writable(_grimoire), do: :ok

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

  defp selected_grimoire_changeset(message \\ "selected grimoire is invalid for this character") do
    %Grimoire{}
    |> Changeset.change()
    |> Changeset.add_error(:id, message)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
