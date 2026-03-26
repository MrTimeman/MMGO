defmodule MMGO.Spells.FailureProfile do
  use Ecto.Schema

  import Ecto.Changeset

  embedded_schema do
    field :difficulty, :integer, default: 1
    field :base_success_rate, :integer, default: 85
    field :partial_success_rate, :integer, default: 10
    field :backlash_damage, :integer, default: 0
    field :volatility, :integer, default: 0
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :difficulty,
      :base_success_rate,
      :partial_success_rate,
      :backlash_damage,
      :volatility
    ])
    |> validate_required([
      :difficulty,
      :base_success_rate,
      :partial_success_rate,
      :backlash_damage
    ])
    |> validate_number(:difficulty, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> validate_number(:base_success_rate,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 100
    )
    |> validate_number(:partial_success_rate,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_number(:backlash_damage, greater_than_or_equal_to: 0)
    |> validate_number(:volatility, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
