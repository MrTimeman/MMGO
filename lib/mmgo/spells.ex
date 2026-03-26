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
end
