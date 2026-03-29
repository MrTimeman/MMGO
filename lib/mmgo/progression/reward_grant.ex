defmodule MMGO.Progression.RewardGrant do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Progression.Milestone
  alias MMGO.Worlds.Realm

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "progression_reward_grants" do
    field :source, :string
    field :granted_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm
    belongs_to :milestone, Milestone

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reward_grant, attrs) do
    reward_grant
    |> cast(attrs, [:source, :granted_at, :metadata, :character_id, :realm_id, :milestone_id])
    |> validate_required([:source, :granted_at, :character_id, :realm_id, :milestone_id])
    |> unique_constraint(:milestone_id,
      name: :progression_reward_grants_character_milestone_index
    )
  end
end
