defmodule MMGO.Events.Instance do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Events.Template
  alias MMGO.Worlds.{Location, Realm}

  @statuses [:active, :resolved]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_instances" do
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :selected_option_code, :string
    field :started_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm
    belongs_to :location, Location
    belongs_to :template, Template

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :status,
      :selected_option_code,
      :started_at,
      :resolved_at,
      :metadata,
      :character_id,
      :realm_id,
      :location_id,
      :template_id
    ])
    |> validate_required([
      :status,
      :started_at,
      :character_id,
      :realm_id,
      :location_id,
      :template_id
    ])
  end
end
