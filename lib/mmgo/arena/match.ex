defmodule MMGO.Arena.Match do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Arena.{MatchMember, Profile}
  alias MMGO.Combat.ArenaEvents
  alias MMGO.Combat.Combat
  alias MMGO.Worlds.Realm

  @modes [:ranked, :custom]
  @statuses [:forming, :queued, :active, :finished, :cancelled]
  @event_policies [:random, :fixed, :none]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "arena_matches" do
    field :mode, Ecto.Enum, values: @modes
    field :status, Ecto.Enum, values: @statuses, default: :forming
    field :team_size, :integer, default: 1
    field :event_policy, Ecto.Enum, values: @event_policies, default: :random
    field :event_codes, {:array, :string}, default: []
    field :settings, :map, default: %{}
    field :metadata, :map, default: %{}
    field :code, :string
    field :seed, :integer
    field :winner_team, Ecto.Enum, values: [:a, :b]
    field :queued_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    belongs_to :host_profile, Profile
    belongs_to :realm, Realm
    belongs_to :combat, Combat
    has_many :members, MatchMember

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [
      :mode,
      :status,
      :team_size,
      :event_policy,
      :event_codes,
      :settings,
      :metadata,
      :code,
      :seed,
      :winner_team,
      :queued_at,
      :started_at,
      :finished_at
    ])
    |> validate_required([
      :mode,
      :status,
      :team_size,
      :event_policy,
      :seed,
      :host_profile_id,
      :realm_id
    ])
    |> validate_number(:team_size, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:seed, greater_than: 0)
    |> validate_length(:code, min: 6, max: 12)
    |> validate_subset(:event_codes, ArenaEvents.event_codes())
    |> validate_code_for_mode()
    |> unique_constraint(:code)
    |> unique_constraint(:combat_id)
    |> unique_constraint(:host_profile_id, name: :arena_matches_single_ranked_queue_index)
    |> check_constraint(:mode, name: :arena_matches_valid_mode)
    |> check_constraint(:status, name: :arena_matches_valid_status)
    |> check_constraint(:team_size, name: :arena_matches_valid_team_size)
    |> check_constraint(:event_policy, name: :arena_matches_valid_event_policy)
    |> check_constraint(:event_codes, name: :arena_matches_allowed_events)
    |> check_constraint(:winner_team, name: :arena_matches_valid_winner)
    |> check_constraint(:code, name: :arena_matches_custom_code)
  end

  defp validate_code_for_mode(changeset) do
    case {get_field(changeset, :mode), get_field(changeset, :code)} do
      {:custom, code} when is_binary(code) -> changeset
      {:ranked, nil} -> changeset
      {:custom, _nil} -> add_error(changeset, :code, "is required for custom rooms")
      {:ranked, _code} -> add_error(changeset, :code, "is not used for ranked matchmaking")
      _other -> changeset
    end
  end
end
