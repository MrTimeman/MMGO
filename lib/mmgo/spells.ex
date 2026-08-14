defmodule MMGO.Spells do
  import Ecto.Query, warn: false

  alias MMGO.Accounts.Character
  alias MMGO.Repo
  alias MMGO.Spells.{CreationAttempt, Spell}

  def list_spells_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from spell in Spell,
        left_join: attempt in CreationAttempt,
        on: attempt.id == spell.creation_attempt_id,
        where: spell.creator_character_id == ^character_id,
        where:
          is_nil(spell.creation_attempt_id) or
            (attempt.status == :revealed and
               fragment("?->>'kind' = 'success'", attempt.outcome)),
        order_by: [asc: spell.inserted_at]
    )
  end

  def get_spell!(id), do: Repo.get!(Spell, id)

  @doc """
  Returns a spell only when it belongs to `character` in the character's
  current realm.

  This is deliberately non-raising because browser and compiler spell IDs are
  untrusted selection hints, not authority.
  """
  def get_owned_spell(%Character{} = character, spell_id) when is_binary(spell_id) do
    Repo.one(
      from spell in Spell,
        left_join: attempt in CreationAttempt,
        on: attempt.id == spell.creation_attempt_id,
        where:
          spell.id == ^spell_id and spell.creator_character_id == ^character.id and
            spell.realm_id == ^character.realm_id,
        where:
          is_nil(spell.creation_attempt_id) or
            (attempt.status == :revealed and
               fragment("?->>'kind' = 'success'", attempt.outcome))
    )
  end

  def get_owned_spell(_character, _spell_id), do: nil

  def create_spell(%Character{} = character, attrs, opts \\ [])
      when is_map(attrs) and is_list(opts) do
    case Keyword.get(opts, :creation_attempt_id) do
      nil ->
        insert_spell(character, attrs, nil)

      creation_attempt_id when is_binary(creation_attempt_id) ->
        create_attempt_spell(character, attrs, creation_attempt_id)

      _invalid_creation_attempt_id ->
        {:error, spell_error(attrs, :creation_attempt_id, "is invalid")}
    end
  end

  def update_spell(%Spell{} = spell, attrs) do
    spell
    |> Spell.changeset(attrs)
    |> Repo.update()
  end

  def change_spell(%Spell{} = spell, attrs \\ %{}) do
    Spell.changeset(spell, attrs)
  end

  @doc """
  Renames one spell.

  A spell's name is what its author calls it, not part of its magic: the formula
  and everything the engine reads are untouched.
  """
  def rename_spell(%Spell{} = spell, name) when is_binary(name) do
    spell
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.cast(%{"name" => String.trim(name)}, [:name])
    |> Ecto.Changeset.validate_required([:name])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: 120)
    |> Repo.update()
  end

  def rename_spell(%Spell{}, _name), do: {:error, spell_error(%{}, :name, "is invalid")}

  @doc """
  Burns one spell out of its author's library for good.

  Every inscription of it is torn out with it, and anything that merely
  remembers it — a lineage, a settled combat, a request log — keeps its record
  and loses the reference. Written spells are cheap to make and a library the
  player cannot prune is a library they stop reading.
  """
  def delete_spell(%Spell{} = spell) do
    Repo.delete(spell)
  end

  @doc """
  Returns whether two magic schools are opposite on the elemental compass.

  Opposed schools may not be selected together for a Wizardry specialization;
  this remains a pure rule so Academy enrollment and direct schema use the
  same definition.
  """
  def opposed_schools?(:fire, :water), do: true
  def opposed_schools?(:water, :fire), do: true
  def opposed_schools?(:earth, :air), do: true
  def opposed_schools?(:air, :earth), do: true
  def opposed_schools?(:chaos, :order), do: true
  def opposed_schools?(:order, :chaos), do: true
  def opposed_schools?(:life, :death), do: true
  def opposed_schools?(:death, :life), do: true
  def opposed_schools?(_first_school, _second_school), do: false

  defp create_attempt_spell(character, attrs, creation_attempt_id) do
    Repo.transaction(fn ->
      attempt =
        CreationAttempt
        |> where([attempt], attempt.id == ^creation_attempt_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      existing_spell =
        Repo.get_by(Spell,
          creation_attempt_id: creation_attempt_id,
          creator_character_id: character.id,
          realm_id: character.realm_id
        )

      cond do
        is_nil(attempt) ->
          Repo.rollback(spell_error(attrs, :creation_attempt_id, "does not exist"))

        attempt.character_id != character.id or attempt.realm_id != character.realm_id ->
          Repo.rollback(spell_error(attrs, :creation_attempt_id, "does not belong to the caster"))

        attempt.status != :resolving ->
          Repo.rollback(spell_error(attrs, :creation_attempt_id, "is not resolving"))

        not is_nil(existing_spell) ->
          existing_spell

        true ->
          case insert_spell(character, attrs, creation_attempt_id) do
            {:ok, spell} -> spell
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  defp insert_spell(character, attrs, creation_attempt_id) do
    %Spell{
      creator_character_id: character.id,
      realm_id: character.realm_id,
      creation_attempt_id: creation_attempt_id
    }
    |> Spell.changeset(attrs)
    |> Repo.insert()
  end

  defp spell_error(attrs, field, message) do
    %Spell{}
    |> Spell.changeset(attrs)
    |> Ecto.Changeset.add_error(field, message)
  end
end
