defmodule MMGO.Dungeons.EncounterSpawn do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Actors.ActorTemplate
  alias MMGO.Dungeons.Encounter

  @statuses [:active, :defeated]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_encounter_spawns" do
    field :quantity, :integer
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :current_hp, :integer
    field :metadata, :map, default: %{}

    belongs_to :encounter, Encounter
    belongs_to :actor_template, ActorTemplate

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(encounter_spawn, attrs) do
    encounter_spawn
    |> cast(attrs, [:quantity, :status, :current_hp, :metadata, :encounter_id, :actor_template_id])
    |> validate_required([:quantity, :status, :current_hp, :encounter_id, :actor_template_id])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:current_hp, greater_than: 0)
  end
end
