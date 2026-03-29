defmodule MMGO.Events.Template do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Events.{Instance, Option}
  alias MMGO.Worlds.Realm

  @location_kinds [:city, :tower, :wilderness, :base]
  @statuses [:active, :archived]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_templates" do
    field :code, :string
    field :location_kind, Ecto.Enum, values: @location_kinds
    field :title, :string
    field :body, :string
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    has_many :options, Option
    has_many :instances, Instance

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:code, :location_kind, :title, :body, :status, :metadata, :realm_id])
    |> validate_required([:code, :location_kind, :title, :body, :status, :realm_id])
    |> validate_length(:code, min: 3, max: 80)
    |> validate_length(:title, min: 3, max: 160)
    |> validate_length(:body, min: 3, max: 1000)
    |> unique_constraint(:code, name: :event_templates_realm_code_index)
  end
end
