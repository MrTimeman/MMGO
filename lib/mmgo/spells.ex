defmodule MMGO.Spells do
  import Ecto.Query, warn: false

  alias MMGO.Accounts.Character
  alias MMGO.Progression
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
    Repo.transaction(fn ->
      character =
        Character
        |> where([character], character.id == ^character.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      case %Spell{creator_character_id: character.id, realm_id: character.realm_id}
           |> Spell.changeset(attrs)
           |> Repo.insert() do
        {:ok, spell} ->
          xp_awarded = spell_creation_xp(spell)

          {:ok, %{character: updated_character}} =
            Progression.grant_xp(Repo, character, xp_awarded, %{
              "source" => "spell_creation",
              "spell_id" => spell.id,
              "granted_at" => DateTime.utc_now()
            })

          %{spell | creator_character: updated_character}

        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def update_spell(%Spell{} = spell, attrs) do
    spell
    |> Spell.changeset(attrs)
    |> Repo.update()
  end

  def change_spell(%Spell{} = spell, attrs \\ %{}) do
    Spell.changeset(spell, attrs)
  end

  defp spell_creation_xp(%Spell{} = spell) do
    difficulty = (spell.failure_profile && spell.failure_profile.difficulty) || 1

    effect_intensity =
      Enum.reduce(spell.effects, 0, fn effect, total -> total + effect.intensity end)

    max(difficulty * 2 + div(effect_intensity, 6), 12)
  end

  defp normalize_transaction_result({:ok, %Spell{} = spell}), do: {:ok, spell}

  defp normalize_transaction_result({:error, %Ecto.Changeset{} = changeset}),
    do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Ecto.Changeset{} = changeset, _changes}),
    do: {:error, changeset}
end
