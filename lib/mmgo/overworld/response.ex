defmodule MMGO.Overworld.Response do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Overworld.Encounter

  @actions [:greet, :trade, :attack, :avoid]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "overworld_encounter_responses" do
    field :action, Ecto.Enum, values: @actions
    field :chosen_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :encounter, Encounter
    belongs_to :actor_character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(response, attrs) do
    response
    |> cast(attrs, [:action, :chosen_at, :metadata, :encounter_id, :actor_character_id])
    |> validate_required([:action, :chosen_at, :encounter_id, :actor_character_id])
    |> unique_constraint(:actor_character_id,
      name: :overworld_encounter_responses_unique_actor_index
    )
  end
end
