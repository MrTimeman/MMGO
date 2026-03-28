defmodule MMGO.Dungeons.Extraction do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Dungeons.Run

  @types [:ascent, :return_ritual]
  @statuses [:active, :completed, :interrupted]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dungeon_extractions" do
    field :extraction_type, Ecto.Enum, values: @types
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :started_at, :utc_datetime_usec
    field :completes_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :run, Run
    belongs_to :initiator_character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(extraction, attrs) do
    extraction
    |> cast(attrs, [
      :extraction_type,
      :status,
      :started_at,
      :completes_at,
      :completed_at,
      :metadata,
      :run_id,
      :initiator_character_id
    ])
    |> validate_required([:extraction_type, :status, :started_at, :run_id])
    |> unique_constraint(:run_id, name: :dungeon_extractions_active_run_index)
  end
end
