defmodule MMGO.Arena.Ranks do
  @moduledoc """
  The rank a character carries into a fight.

  Rank is earned on the ladder and spent everywhere: it is what decides which
  spells a caster may wield, in ranked play and in the world alike. A player may
  keep several arena profiles, so the rank that follows them is the strongest
  division any of their profiles holds — a rank is earned once, not once per
  character.

  Someone who has never entered the arena stands at the foot of the ladder and
  may wield only the plainest craft until they do.
  """

  import Ecto.Query, warn: false

  alias MMGO.Accounts.Character
  alias MMGO.Arena.{Ladder, Profile}
  alias MMGO.Repo

  @doc "The rank a character carries, from the account that owns them."
  def for_character(%Character{account_id: account_id}), do: for_account(account_id)

  def for_character(character_id) when is_binary(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> select([character], character.account_id)
    |> Repo.one()
    |> for_account()
  end

  def for_character(_character), do: base_rank()

  @doc "The strongest division any of the account's arena profiles holds."
  def for_account(account_id) when is_binary(account_id) do
    Profile
    |> where([profile], profile.account_id == ^account_id)
    |> select([profile], profile.division)
    |> Repo.all()
    |> highest()
  end

  def for_account(_account_id), do: base_rank()

  defp highest([]), do: base_rank()

  defp highest(divisions), do: Enum.max_by(divisions, &Ladder.ordinal/1)

  defp base_rank, do: hd(Ladder.keys())
end
