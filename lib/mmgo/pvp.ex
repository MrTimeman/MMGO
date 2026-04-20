defmodule MMGO.PVP do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Combat
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Economy
  alias MMGO.PVP.Duel
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  def list_open_duels_for_character(character_id) when is_binary(character_id) do
    Duel
    |> where(
      [duel],
      (duel.challenger_character_id == ^character_id or
         duel.opponent_character_id == ^character_id) and
        duel.status in [:pending, :active]
    )
    |> order_by([duel], asc: duel.inserted_at)
    |> Repo.all()
  end

  def get_duel!(id) do
    Duel
    |> Repo.get!(id)
    |> Repo.preload([
      :challenger_character,
      :opponent_character,
      :winner_character,
      :combat,
      :escrow_account
    ])
  end

  def pending_duels_for_character(character_id) when is_binary(character_id) do
    Duel
    |> where(
      [duel],
      (duel.challenger_character_id == ^character_id or
         duel.opponent_character_id == ^character_id) and
        duel.status == :pending
    )
    |> order_by([duel], asc: duel.inserted_at)
    |> Repo.all()
  end

  def active_duel_for_character(character_id) when is_binary(character_id) do
    Duel
    |> where(
      [duel],
      (duel.challenger_character_id == ^character_id or
         duel.opponent_character_id == ^character_id) and
        duel.status == :active
    )
    |> Repo.one()
  end

  def challenge_duel(
        %Character{} = challenger,
        %Character{} = opponent,
        stake_amount,
        attrs \\ %{}
      )
      when is_integer(stake_amount) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      challenger = lock_character!(challenger.id)
      opponent = lock_character!(opponent.id)
      validate_challenge!(challenger, opponent, stake_amount)

      %Duel{}
      |> Duel.changeset(%{
        realm_id: challenger.realm_id,
        challenger_character_id: challenger.id,
        opponent_character_id: opponent.id,
        stake_amount: stake_amount,
        pot_amount: stake_amount * 2,
        tax_rate_bps: attrs["tax_rate_bps"] || tax_rate_bps(),
        status: :pending,
        challenged_at: DateTime.utc_now(),
        metadata: attrs["metadata"] || %{}
      })
      |> Repo.insert!()
    end)
    |> normalize_transaction_result()
  end

  def reject_duel(%Duel{} = duel, %Character{} = actor) do
    Repo.transaction(fn ->
      duel = lock_duel!(duel.id)

      cond do
        duel.status != :pending ->
          Repo.rollback(duel_changeset("duel is not pending"))

        duel.opponent_character_id != actor.id ->
          Repo.rollback(duel_changeset("only the opponent can reject this duel"))

        true ->
          duel
          |> Duel.changeset(%{status: :rejected, resolved_at: DateTime.utc_now()})
          |> Repo.update!()
      end
    end)
    |> normalize_transaction_result()
  end

  def accept_duel(%Duel{} = duel) do
    Repo.transaction(fn ->
      duel = lock_duel!(duel.id)
      challenger = lock_character!(duel.challenger_character_id)
      opponent = lock_character!(duel.opponent_character_id)

      validate_acceptance!(duel, challenger, opponent)

      {:ok, challenger_account} = Economy.ensure_character_account(challenger)
      {:ok, opponent_account} = Economy.ensure_character_account(opponent)
      realm = Repo.get!(Realm, duel.realm_id)

      {:ok, escrow_account} =
        Economy.create_escrow_account(realm, %{duel_id: duel.id, type: "duel_wager"})

      {:ok, _first_funding} =
        Economy.transfer(challenger_account, escrow_account, duel.stake_amount, %{
          entry_type: "wager",
          source: "pvp_duel",
          duel_id: duel.id,
          role: "challenger"
        })

      {:ok, _second_funding} =
        Economy.transfer(opponent_account, escrow_account, duel.stake_amount, %{
          entry_type: "wager",
          source: "pvp_duel",
          duel_id: duel.id,
          role: "opponent"
        })

      location_kind = location_kind(challenger.current_location_id)

      {:ok, %{combat: combat}} =
        Combat.create_duel(realm, %{
          participants: [
            %{character_id: challenger.id, side: "attackers", position: 0},
            %{character_id: opponent.id, side: "defenders", position: 0}
          ],
          metadata: %{
            duel_id: duel.id,
            challenger_character_id: challenger.id,
            opponent_character_id: opponent.id,
            location_id: challenger.current_location_id,
            location_kind: location_kind
          }
        })

      duel
      |> Duel.changeset(%{
        status: :active,
        accepted_at: DateTime.utc_now(),
        escrow_account_id: escrow_account.id,
        combat_id: combat.id
      })
      |> Repo.update!()
      |> Repo.preload([:challenger_character, :opponent_character, :combat, :escrow_account])
    end)
    |> normalize_transaction_result()
  end

  def cancel_duel(%Duel{} = duel, %Character{} = actor) do
    Repo.transaction(fn ->
      duel = lock_duel!(duel.id)

      cond do
        duel.status == :pending ->
          if duel.challenger_character_id != actor.id do
            Repo.rollback(duel_changeset("only the challenger can cancel a pending duel"))
          end

          duel
          |> Duel.changeset(%{status: :cancelled, resolved_at: DateTime.utc_now()})
          |> Repo.update!()

        duel.status == :active ->
          if actor.id not in [duel.challenger_character_id, duel.opponent_character_id] do
            Repo.rollback(duel_changeset("only duel participants can cancel an active duel"))
          end

          duel = refund_duel!(duel)

          duel
          |> Duel.changeset(%{status: :cancelled, resolved_at: DateTime.utc_now()})
          |> Repo.update!()

        true ->
          Repo.rollback(duel_changeset("duel cannot be cancelled from its current state"))
      end
    end)
    |> normalize_transaction_result()
  end

  def settle_duel_from_combat(%CombatSchema{} = combat) do
    Repo.transaction(fn ->
      combat = Combat.get_combat!(combat.id)

      if combat.kind != :duel do
        Repo.rollback(duel_changeset("combat is not a duel"))
      end

      if combat.status != :finished do
        Repo.rollback(duel_changeset("combat is not finished"))
      end

      duel_id = combat.metadata["duel_id"] || combat.metadata[:duel_id]
      duel = lock_duel!(duel_id)

      if duel.status != :active do
        Repo.rollback(duel_changeset("duel is not active"))
      end

      duel =
        case combat.winner_side do
          "attackers" -> payout_duel!(duel, duel.challenger_character_id)
          "defenders" -> payout_duel!(duel, duel.opponent_character_id)
          _other -> refund_duel!(duel)
        end

      award_duel_xp!(duel)

      duel
      |> Duel.changeset(%{
        status: :resolved,
        winner_character_id: duel.winner_character_id,
        resolved_at: DateTime.utc_now()
      })
      |> Repo.update!()
      |> Repo.preload([
        :challenger_character,
        :opponent_character,
        :winner_character,
        :combat,
        :escrow_account
      ])
    end)
    |> normalize_transaction_result()
  end

  defp validate_challenge!(%Character{} = challenger, %Character{} = opponent, stake_amount) do
    cond do
      challenger.id == opponent.id ->
        Repo.rollback(duel_changeset("character cannot duel themselves"))

      challenger.realm_id != opponent.realm_id ->
        Repo.rollback(duel_changeset("duel participants must belong to the same realm"))

      stake_amount <= 0 ->
        Repo.rollback(duel_changeset("stake amount must be greater than zero"))

      active_open_duel?(challenger.id) ->
        Repo.rollback(duel_changeset("challenger already has an open duel"))

      active_open_duel?(opponent.id) ->
        Repo.rollback(duel_changeset("opponent already has an open duel"))

      Combat.active_combat_for_character(challenger.id) ->
        Repo.rollback(duel_changeset("challenger already has an active combat"))

      Combat.active_combat_for_character(opponent.id) ->
        Repo.rollback(duel_changeset("opponent already has an active combat"))

      true ->
        :ok
    end
  end

  defp validate_acceptance!(%Duel{} = duel, %Character{} = challenger, %Character{} = opponent) do
    cond do
      duel.status != :pending ->
        Repo.rollback(duel_changeset("duel is not pending"))

      active_open_duel?(challenger.id, duel.id) ->
        Repo.rollback(duel_changeset("challenger already has another open duel"))

      active_open_duel?(opponent.id, duel.id) ->
        Repo.rollback(duel_changeset("opponent already has another open duel"))

      Combat.active_combat_for_character(challenger.id) ->
        Repo.rollback(duel_changeset("challenger already has an active combat"))

      Combat.active_combat_for_character(opponent.id) ->
        Repo.rollback(duel_changeset("opponent already has an active combat"))

      challenger.current_location_id != opponent.current_location_id ->
        Repo.rollback(duel_changeset("duel participants must be at the same location"))

      insufficient_funds?(challenger, duel.stake_amount) ->
        Repo.rollback(duel_changeset("challenger lacks the required stake"))

      insufficient_funds?(opponent, duel.stake_amount) ->
        Repo.rollback(duel_changeset("opponent lacks the required stake"))

      true ->
        :ok
    end
  end

  defp payout_duel!(%Duel{} = duel, winner_character_id) do
    escrow_account = Repo.get!(Economy.EconomyAccount, duel.escrow_account_id)
    winner_character = Repo.get!(Character, winner_character_id)
    {:ok, winner_account} = Economy.ensure_character_account(winner_character)

    {:ok, _ledger_result} =
      Economy.taxed_transfer(
        escrow_account,
        winner_account,
        duel.pot_amount,
        duel.tax_rate_bps,
        %{
          entry_type: "wager",
          source: "pvp_duel_settlement",
          duel_id: duel.id,
          winner_character_id: winner_character_id
        }
      )

    %{duel | winner_character_id: winner_character_id}
  end

  defp refund_duel!(%Duel{} = duel) do
    escrow_account = Repo.get!(Economy.EconomyAccount, duel.escrow_account_id)
    challenger = Repo.get!(Character, duel.challenger_character_id)
    opponent = Repo.get!(Character, duel.opponent_character_id)
    {:ok, challenger_account} = Economy.ensure_character_account(challenger)
    {:ok, opponent_account} = Economy.ensure_character_account(opponent)

    {:ok, _refund_one} =
      Economy.transfer(escrow_account, challenger_account, duel.stake_amount, %{
        entry_type: "wager",
        source: "pvp_duel_refund",
        duel_id: duel.id,
        role: "challenger"
      })

    {:ok, _refund_two} =
      Economy.transfer(escrow_account, opponent_account, duel.stake_amount, %{
        entry_type: "wager",
        source: "pvp_duel_refund",
        duel_id: duel.id,
        role: "opponent"
      })

    %{duel | winner_character_id: nil}
  end

  defp award_duel_xp!(%Duel{} = duel) do
    challenger = Repo.get!(Character, duel.challenger_character_id)
    opponent = Repo.get!(Character, duel.opponent_character_id)
    base_xp = max(div(duel.pot_amount, 2), 12)
    winner_bonus = max(div(base_xp, 2), 4)
    now = DateTime.utc_now()

    challenger_amount =
      if duel.winner_character_id == challenger.id, do: base_xp + winner_bonus, else: base_xp

    opponent_amount =
      if duel.winner_character_id == opponent.id, do: base_xp + winner_bonus, else: base_xp

    {:ok, _challenger_result} =
      Progression.grant_xp(Repo, challenger, challenger_amount, %{
        "source" => "duel_resolution",
        "duel_id" => duel.id,
        "combat_id" => duel.combat_id,
        "granted_at" => now,
        "result" =>
          if(duel.winner_character_id == challenger.id, do: "winner", else: "participant")
      })

    {:ok, _opponent_result} =
      Progression.grant_xp(Repo, opponent, opponent_amount, %{
        "source" => "duel_resolution",
        "duel_id" => duel.id,
        "combat_id" => duel.combat_id,
        "granted_at" => now,
        "result" => if(duel.winner_character_id == opponent.id, do: "winner", else: "participant")
      })
  end

  defp insufficient_funds?(%Character{} = character, amount) do
    case Economy.ensure_character_account(character) do
      {:ok, account} -> account.current_balance < amount
      _other -> true
    end
  end

  defp active_open_duel?(character_id, except_duel_id \\ nil) do
    Duel
    |> where(
      [duel],
      (duel.challenger_character_id == ^character_id or
         duel.opponent_character_id == ^character_id) and
        duel.status in [:pending, :active]
    )
    |> maybe_exclude_duel(except_duel_id)
    |> Repo.exists?()
  end

  defp maybe_exclude_duel(query, nil), do: query
  defp maybe_exclude_duel(query, duel_id), do: where(query, [duel], duel.id != ^duel_id)

  defp lock_duel!(duel_id) do
    Duel
    |> where([duel], duel.id == ^duel_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp location_kind(nil), do: nil

  defp location_kind(location_id) do
    MMGO.Worlds.get_location!(location_id).kind |> to_string()
  rescue
    Ecto.NoResultsError -> nil
  end

  defp tax_rate_bps do
    Application.get_env(:mmgo, __MODULE__, [])[:duel_tax_rate_bps] || 500
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp duel_changeset(message) do
    %Duel{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
