defmodule MMGO.Actors.ActorTemplate do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Worlds.Realm

  @roles [:hostile, :neutral, :friendly]
  @behavior_profiles [:aggressive, :defensive, :support, :passive]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "actor_templates" do
    field :code, :string
    field :name, :string
    field :role, Ecto.Enum, values: @roles
    field :combat_level, :integer
    field :base_hp, :integer
    field :behavior_profile, Ecto.Enum, values: @behavior_profiles, default: :aggressive
    field :tags, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(actor_template, attrs) do
    actor_template
    |> cast(attrs, [
      :code,
      :name,
      :role,
      :combat_level,
      :base_hp,
      :behavior_profile,
      :tags,
      :metadata,
      :realm_id
    ])
    |> validate_required([:code, :name, :role, :combat_level, :base_hp, :realm_id])
    |> validate_length(:code, min: 3, max: 80)
    |> validate_length(:name, min: 2, max: 120)
    |> validate_number(:combat_level, greater_than: 0)
    |> validate_number(:base_hp, greater_than: 0)
    |> unique_constraint(:code, name: :actor_templates_realm_code_index)
  end
end
