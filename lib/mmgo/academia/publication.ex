defmodule MMGO.Academia.Publication do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Worlds.Realm

  @publication_kinds [:spell, :potion, :tool, :thesis, :course]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "academia_publications" do
    field :publication_kind, Ecto.Enum, values: @publication_kinds
    field :title, :string
    field :code, :string
    field :published_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :author_character, Character
    belongs_to :realm, Realm

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(publication, attrs) do
    publication
    |> cast(attrs, [
      :publication_kind,
      :title,
      :code,
      :published_at,
      :metadata,
      :author_character_id,
      :realm_id
    ])
    |> validate_required([
      :publication_kind,
      :title,
      :code,
      :published_at,
      :author_character_id,
      :realm_id
    ])
    |> validate_length(:title, min: 3, max: 160)
    |> validate_length(:code, min: 3, max: 200)
    |> unique_constraint(:code)
  end
end
