defmodule MMGO.Alchemy.Workshop do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Alchemy.BrewJob
  alias MMGO.Worlds.{Location, Realm}

  @statuses [:active, :inactive]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "alchemy_workspaces" do
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :installed_tool_codes, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    belongs_to :owner_character, Character
    belongs_to :realm, Realm
    belongs_to :location, Location
    has_many :brew_jobs, BrewJob, foreign_key: :workspace_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(workshop, attrs) do
    workshop
    |> cast(attrs, [
      :name,
      :status,
      :installed_tool_codes,
      :metadata,
      :owner_character_id,
      :realm_id,
      :location_id
    ])
    |> validate_required([:name, :status, :owner_character_id, :realm_id, :location_id])
    |> validate_length(:name, min: 3, max: 120)
    |> unique_constraint(:owner_character_id, name: :alchemy_workspaces_active_owner_index)
  end
end
