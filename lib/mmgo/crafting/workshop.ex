defmodule MMGO.Crafting.Workshop do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Crafting.CraftJob
  alias MMGO.Worlds.{Location, Realm}

  @statuses [:active, :inactive]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "crafting_workshops" do
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :installed_tool_codes, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    belongs_to :owner_character, Character
    belongs_to :realm, Realm
    belongs_to :location, Location
    has_many :craft_jobs, CraftJob, foreign_key: :workspace_id

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
    |> unique_constraint(:owner_character_id, name: :crafting_workshops_active_owner_index)
  end
end
