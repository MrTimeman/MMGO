defmodule MMGO.Grimoires.Bookmark do
  @moduledoc """
  A ribbon the player tucks into their own book.

  Bookmarks are not derived from anything — not from schools, not from power,
  not from how often a spell is cast. The player makes them, names them, orders
  them, and decides which page each one opens. That is the whole point: the
  book is theirs, and how it is organised is a thing they did.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Grimoires.Grimoire

  # The set a player may choose from. Bounded on the server so a ribbon can
  # never carry arbitrary markup, and small enough that the choice means
  # something.
  @icons ~w(✦ ≈ ▲ ≋ ✚ ✖ ✧ ◈ ★ ☾ ⚔ ⚑ ❦ ✶)

  # Likewise the palette: a ribbon is one of these or it is plain.
  @colours ~w(#a8453e #3b6ea5 #4a7a5c #a9791f #6b5b9a #7a6a5c)

  @max_label_bytes 24
  @control_character_pattern ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "grimoire_bookmarks" do
    field :label, :string
    field :page, :integer, default: 1
    field :position, :integer, default: 0
    field :colour, :string
    field :icon, :string

    belongs_to :grimoire, Grimoire

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(bookmark, attrs) do
    bookmark
    |> cast(attrs, [:grimoire_id, :label, :page, :position, :colour, :icon])
    |> update_change(:label, &String.trim/1)
    |> validate_required([:grimoire_id, :label, :page])
    |> validate_length(:label, min: 1, max: @max_label_bytes, count: :bytes)
    |> validate_number(:page, greater_than: 0)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_format(:label, ~r/^[^\x00-\x08\x0B\x0C\x0E-\x1F\x7F]+$/u,
      message: "must not contain control characters"
    )
    |> validate_colour()
    |> validate_inclusion(:icon, @icons)
    |> foreign_key_constraint(:grimoire_id)
    |> unique_constraint([:grimoire_id, :label])
  end

  def max_label_bytes, do: @max_label_bytes

  @doc "Every glyph a ribbon may carry."
  def icons, do: @icons

  @doc "Every colour a ribbon may carry."
  def colours, do: @colours

  # A ribbon's colour is chosen from the book's own palette, never from an
  # arbitrary string a browser offered.
  defp validate_colour(changeset) do
    validate_change(changeset, :colour, fn :colour, colour ->
      cond do
        is_nil(colour) -> []
        Regex.match?(@control_character_pattern, colour) -> [colour: "is invalid"]
        colour in @colours -> []
        true -> [colour: "is invalid"]
      end
    end)
  end
end
