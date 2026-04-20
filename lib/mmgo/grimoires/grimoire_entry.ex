defmodule MMGO.Grimoires.GrimoireEntry do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Grimoires.Grimoire
  alias MMGO.Spells.Spell

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "grimoire_entries" do
    field :slot_index, :integer
    field :inscribed_at, :utc_datetime_usec

    belongs_to :grimoire, Grimoire
    belongs_to :spell, Spell

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:grimoire_id, :spell_id, :slot_index])
    |> validate_required([:grimoire_id, :spell_id, :slot_index])
    |> validate_number(:slot_index, greater_than: 0)
    |> unique_constraint(:spell_id, name: :grimoire_entries_grimoire_spell_index)
    |> unique_constraint(:slot_index, name: :grimoire_entries_grimoire_slot_index)
  end
end
