defmodule MMGO.Parties.Reward do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Dungeons.{Encounter, Run}
  alias MMGO.Parties.Expedition

  @reward_kinds [:xp]
  @source_types [:encounter, :run]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "expedition_rewards" do
    field :reward_kind, Ecto.Enum, values: @reward_kinds
    field :source_type, Ecto.Enum, values: @source_types
    field :reward_code, :string
    field :amount, :integer
    field :granted_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :expedition, Expedition
    belongs_to :run, Run
    belongs_to :encounter, Encounter
    belongs_to :character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reward, attrs) do
    reward
    |> cast(attrs, [
      :reward_kind,
      :source_type,
      :reward_code,
      :amount,
      :granted_at,
      :metadata,
      :expedition_id,
      :run_id,
      :encounter_id,
      :character_id
    ])
    |> validate_required([
      :reward_kind,
      :source_type,
      :reward_code,
      :amount,
      :granted_at,
      :expedition_id,
      :run_id,
      :character_id
    ])
    |> validate_number(:amount, greater_than: 0)
    |> validate_source_reference()
    |> unique_constraint(:reward_code)
  end

  defp validate_source_reference(changeset) do
    case get_field(changeset, :source_type) do
      :encounter -> validate_required(changeset, [:encounter_id])
      :run -> changeset
      _other -> changeset
    end
  end
end
