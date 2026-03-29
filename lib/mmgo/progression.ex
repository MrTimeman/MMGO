defmodule MMGO.Progression do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Progression.{Milestone, RewardGrant}
  alias MMGO.Repo

  @max_level 100
  @total_xp_cap 1_000_000

  def list_milestones do
    Repo.all(
      from milestone in Milestone,
        where: milestone.status == :active,
        order_by: [asc: milestone.level]
    )
  end

  def create_milestone(attrs \\ %{}) do
    %Milestone{}
    |> Milestone.changeset(stringify_keys(attrs))
    |> Repo.insert()
  end

  def grant_xp(%Character{} = character, amount, attrs) when is_integer(amount) do
    grant_xp(Repo, character, amount, attrs)
  end

  def grant_xp(repo \\ Repo, %Character{} = character, amount, attrs \\ %{})
      when is_integer(amount) do
    cond do
      amount <= 0 -> {:ok, %{character: character, xp_gained: 0, grants: []}}
      true -> do_grant_xp(repo, character, amount, stringify_keys(attrs))
    end
  end

  def xp_to_level(xp) when is_integer(xp) and xp >= 0 do
    1..@max_level
    |> Enum.reduce_while(1, fn level, _acc ->
      if xp >= xp_for_level(level) do
        {:cont, level}
      else
        {:halt, max(level - 1, 1)}
      end
    end)
  end

  def xp_for_level(level) when is_integer(level) and level >= 1 do
    ratio = (level - 1) / max(@max_level - 1, 1)
    round(ratio * ratio * @total_xp_cap)
  end

  def list_reward_grants(character_id) when is_binary(character_id) do
    Repo.all(
      from reward_grant in RewardGrant,
        where: reward_grant.character_id == ^character_id,
        order_by: [asc: reward_grant.inserted_at]
    )
  end

  defp do_grant_xp(repo, %Character{} = character, amount, attrs) do
    repo.transaction(fn ->
      character =
        Character
        |> where([character], character.id == ^character.id)
        |> lock("FOR UPDATE")
        |> repo.one!()

      previous_level = character.level
      updated_xp = character.xp + amount
      updated_level = xp_to_level(updated_xp)

      grants =
        if updated_level > previous_level do
          apply_milestones(repo, character, previous_level, updated_level, attrs)
        else
          []
        end

      updated_metadata = apply_grant_effects(character.metadata || %{}, grants)

      updated_character =
        character
        |> Character.changeset(%{
          xp: updated_xp,
          level: updated_level,
          metadata: updated_metadata
        })
        |> repo.update!()

      %{character: updated_character, xp_gained: amount, grants: grants}
    end)
    |> normalize_transaction_result()
  end

  defp apply_milestones(repo, %Character{} = character, previous_level, updated_level, attrs) do
    milestones =
      Milestone
      |> where(
        [milestone],
        milestone.status == :active and milestone.level > ^previous_level and
          milestone.level <= ^updated_level
      )
      |> order_by([milestone], asc: milestone.level)
      |> repo.all()

    Enum.map(milestones, fn milestone ->
      %RewardGrant{}
      |> RewardGrant.changeset(%{
        character_id: character.id,
        realm_id: character.realm_id,
        milestone_id: milestone.id,
        source: attrs["source"] || "xp_grant",
        granted_at: attrs["granted_at"] || DateTime.utc_now(),
        metadata: attrs
      })
      |> repo.insert!()
      |> Repo.preload(:milestone)
    end)
  end

  defp apply_grant_effects(metadata, grants) do
    Enum.reduce(grants, metadata, fn grant, acc ->
      effects = grant.milestone.effects || %{}

      Enum.reduce(effects, acc, fn {key, value}, meta_acc ->
        key = to_string(key)

        cond do
          is_integer(value) -> Map.update(meta_acc, key, value, &(&1 + value))
          true -> Map.put(meta_acc, key, value)
        end
      end)
    end)
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
