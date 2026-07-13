defmodule MMGO.Spells do
  import Ecto.Query, warn: false

  alias MMGO.Accounts.Character
  alias MMGO.Repo
  alias MMGO.Spells.Spell

  def list_spells_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from spell in Spell,
        where: spell.creator_character_id == ^character_id,
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
        where:
          spell.id == ^spell_id and spell.creator_character_id == ^character.id and
            spell.realm_id == ^character.realm_id
    )
  end

  def get_owned_spell(_character, _spell_id), do: nil

  def create_spell(%Character{} = character, attrs) when is_map(attrs) do
    %Spell{creator_character_id: character.id, realm_id: character.realm_id}
    |> Spell.changeset(attrs)
    |> Repo.insert()
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
end
