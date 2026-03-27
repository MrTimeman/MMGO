defmodule MMGO.AI.Request do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Combat.{Combat, Turn}
  alias MMGO.Spells.Spell

  @kinds [:spell_compile, :turn_narration]
  @statuses [:succeeded, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ai_requests" do
    field :kind, Ecto.Enum, values: @kinds
    field :status, Ecto.Enum, values: @statuses
    field :provider, :string
    field :model, :string
    field :prompt_version, :string
    field :request_payload, :map, default: %{}
    field :response_payload, :map, default: %{}
    field :latency_ms, :integer
    field :error, :string
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :spell, Spell
    belongs_to :combat, Combat
    belongs_to :combat_turn, Turn

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :kind,
      :status,
      :provider,
      :model,
      :prompt_version,
      :request_payload,
      :response_payload,
      :latency_ms,
      :error,
      :metadata,
      :character_id,
      :spell_id,
      :combat_id,
      :combat_turn_id
    ])
    |> validate_required([
      :kind,
      :status,
      :provider,
      :model,
      :prompt_version,
      :request_payload,
      :response_payload,
      :latency_ms
    ])
    |> validate_length(:provider, min: 3, max: 120)
    |> validate_length(:model, min: 3, max: 120)
    |> validate_number(:latency_ms, greater_than_or_equal_to: 0)
  end
end
