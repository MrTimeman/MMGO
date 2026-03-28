defmodule MMGO.PVP.Duel do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character
  alias MMGO.Combat.Combat
  alias MMGO.Economy.EconomyAccount
  alias MMGO.Worlds.Realm

  @statuses [:pending, :active, :resolved, :rejected, :cancelled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "pvp_duels" do
    field :stake_amount, :integer
    field :pot_amount, :integer
    field :tax_rate_bps, :integer, default: 0
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :challenged_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :realm, Realm
    belongs_to :challenger_character, Character
    belongs_to :opponent_character, Character
    belongs_to :winner_character, Character
    belongs_to :escrow_account, EconomyAccount
    belongs_to :combat, Combat

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(duel, attrs) do
    duel
    |> cast(attrs, [
      :stake_amount,
      :pot_amount,
      :tax_rate_bps,
      :status,
      :challenged_at,
      :accepted_at,
      :resolved_at,
      :metadata,
      :realm_id,
      :challenger_character_id,
      :opponent_character_id,
      :winner_character_id,
      :escrow_account_id,
      :combat_id
    ])
    |> validate_required([
      :stake_amount,
      :pot_amount,
      :tax_rate_bps,
      :status,
      :challenged_at,
      :realm_id,
      :challenger_character_id,
      :opponent_character_id
    ])
    |> validate_number(:stake_amount, greater_than: 0)
    |> validate_number(:pot_amount, greater_than: 0)
    |> validate_number(:tax_rate_bps, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000)
    |> validate_distinct_participants()
  end

  defp validate_distinct_participants(changeset) do
    if get_field(changeset, :challenger_character_id) ==
         get_field(changeset, :opponent_character_id) do
      add_error(changeset, :opponent_character_id, "must differ from the challenger")
    else
      changeset
    end
  end
end
