defmodule MMGO.Academia.ProfessorReputation do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Worlds.Realm

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "professor_reputation" do
    field :score, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :professor_character, Character, foreign_key: :professor_character_id
    belongs_to :realm, Realm

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reputation, attrs) do
    reputation
    |> cast(attrs, [:score, :metadata, :professor_character_id, :realm_id])
    |> validate_required([:score, :professor_character_id, :realm_id])
    |> unique_constraint([:professor_character_id, :realm_id],
      name: :professor_reputation_character_realm_index
    )
  end
end
