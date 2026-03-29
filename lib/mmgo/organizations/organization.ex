defmodule MMGO.Organizations.Organization do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Organizations.{Invitation, Membership, Role}
  alias MMGO.Worlds.Realm

  @kinds [:cult, :company, :council, :guild]
  @statuses [:active, :archived]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organizations" do
    field :name, :string
    field :kind, Ecto.Enum, values: @kinds
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :hierarchy_rules, :map, default: %{}
    field :fast_travel_enabled, :boolean, default: false
    field :linked_location_ids, {:array, :binary_id}, default: []
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :founder_character, Character
    has_many :roles, Role
    has_many :memberships, Membership
    has_many :invitations, Invitation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [
      :name,
      :kind,
      :status,
      :hierarchy_rules,
      :fast_travel_enabled,
      :linked_location_ids,
      :metadata,
      :realm_id,
      :founder_character_id
    ])
    |> validate_required([:name, :kind, :status, :realm_id, :founder_character_id])
    |> validate_length(:name, min: 3, max: 160)
  end
end
