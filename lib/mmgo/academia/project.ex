defmodule MMGO.Academia.Project do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Academia.Publication
  alias MMGO.Worlds.Realm

  @project_kinds [:spell, :potion, :tool, :thesis, :course]
  @statuses [:active, :completed, :failed, :cancelled]
  @defense_states [
    :pending_defense,
    :under_review,
    :accepted,
    :accepted_with_revisions,
    :rejected
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "academia_projects" do
    field :project_kind, Ecto.Enum, values: @project_kinds
    field :title, :string
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :started_at, :utc_datetime_usec
    field :completes_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :defense_scheduled_at, :utc_datetime_usec
    field :defense_state, Ecto.Enum, values: @defense_states
    field :metadata, :map, default: %{}

    belongs_to :character, Character
    belongs_to :realm, Realm
    belongs_to :publication, Publication

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :project_kind,
      :title,
      :status,
      :started_at,
      :completes_at,
      :completed_at,
      :defense_scheduled_at,
      :defense_state,
      :metadata,
      :character_id,
      :realm_id,
      :publication_id
    ])
    |> validate_required([
      :project_kind,
      :title,
      :status,
      :started_at,
      :completes_at,
      :character_id,
      :realm_id
    ])
    |> validate_length(:title, min: 3, max: 160)
    |> unique_constraint(:character_id, name: :academia_projects_active_character_index)
  end
end
