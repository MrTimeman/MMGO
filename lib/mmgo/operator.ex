defmodule MMGO.Operator do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Academy
  alias MMGO.Academy.Enrollment
  alias MMGO.Combat.Combat
  alias MMGO.Dungeons.Run
  alias MMGO.Economy.EconomyAccount
  alias MMGO.Market.Listing
  alias MMGO.Notifications.Notification
  alias MMGO.Operator.AuditEvent
  alias MMGO.Parties.Expedition
  alias MMGO.Repo
  alias MMGO.Scavenging
  alias MMGO.Scavenging.Attempt
  alias MMGO.Travel
  alias MMGO.Travel.Journey
  alias MMGO.Worlds.{Location, Realm, Route}
  alias MMGO.Accounts.Character

  def system_report do
    %{
      realms: Repo.aggregate(Realm, :count, :id),
      characters: Repo.aggregate(Character, :count, :id),
      locations: Repo.aggregate(Location, :count, :id),
      routes: Repo.aggregate(Route, :count, :id),
      active_journeys: count_active(Journey),
      active_enrollments: count_active(Enrollment),
      active_scavenge_attempts: count_active(Attempt),
      active_expeditions: count_active(Expedition),
      active_runs: count_active(Run),
      active_combats: count_combat_active(),
      active_market_listings: count_active(Listing),
      pending_notifications: count_status(Notification, :pending),
      treasury_balance_total: balance_total(:treasury),
      character_balance_total: balance_total(:character)
    }
  end

  def realm_report(realm_slug) when is_binary(realm_slug) do
    case Repo.get_by(Realm, slug: realm_slug) do
      nil -> {:error, report_changeset("realm could not be found")}
      realm -> {:ok, realm_report(realm)}
    end
  end

  def realm_report(%Realm{} = realm) do
    %{
      realm: %{id: realm.id, slug: realm.slug, name: realm.name, status: realm.status},
      characters:
        Repo.aggregate(
          from(character in Character, where: character.realm_id == ^realm.id),
          :count,
          :id
        ),
      locations:
        Repo.aggregate(
          from(location in Location, where: location.realm_id == ^realm.id),
          :count,
          :id
        ),
      routes:
        Repo.aggregate(from(route in Route, where: route.realm_id == ^realm.id), :count, :id),
      active_journeys:
        Repo.aggregate(
          from(journey in Journey,
            where: journey.realm_id == ^realm.id and journey.status == :active
          ),
          :count,
          :id
        ),
      active_enrollments:
        Repo.aggregate(
          from(enrollment in Enrollment,
            where: enrollment.realm_id == ^realm.id and enrollment.status == :active
          ),
          :count,
          :id
        ),
      active_scavenge_attempts:
        Repo.aggregate(
          from(attempt in Attempt,
            where: attempt.realm_id == ^realm.id and attempt.status == :active
          ),
          :count,
          :id
        ),
      active_expeditions:
        Repo.aggregate(
          from(expedition in Expedition,
            where: expedition.realm_id == ^realm.id and expedition.status == :active
          ),
          :count,
          :id
        ),
      active_runs:
        Repo.aggregate(
          from(run in Run,
            join: expedition in assoc(run, :expedition),
            where: expedition.realm_id == ^realm.id and run.status == :active
          ),
          :count,
          :id
        ),
      active_combats:
        Repo.aggregate(
          from(combat in Combat,
            where:
              combat.realm_id == ^realm.id and
                combat.status in [:active_turn, :locked, :resolving]
          ),
          :count,
          :id
        ),
      active_market_listings:
        Repo.aggregate(
          from(listing in Listing,
            where: listing.realm_id == ^realm.id and listing.status == :active
          ),
          :count,
          :id
        ),
      treasury_balance:
        Repo.aggregate(
          from(account in EconomyAccount,
            where: account.realm_id == ^realm.id and account.owner_type == :treasury
          ),
          :sum,
          :current_balance
        ) || 0,
      character_balance_total:
        Repo.aggregate(
          from(account in EconomyAccount,
            where: account.realm_id == ^realm.id and account.owner_type == :character
          ),
          :sum,
          :current_balance
        ) || 0
    }
  end

  def maintenance_sweep(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    actor_handle = Keyword.get(opts, :actor_handle, "system")

    Repo.transaction(fn ->
      journeys = Travel.complete_due_journeys(now)
      enrollments = Academy.complete_due_enrollments(now)
      attempts = Scavenging.complete_due_attempts(now)
      refreshed_caches = Scavenging.refresh_due_resource_caches(now)

      summary = %{
        completed_journeys: count_ok(journeys),
        completed_enrollments: count_ok(enrollments),
        completed_attempts: count_ok(attempts),
        refreshed_resource_caches: length(refreshed_caches)
      }

      audit_event =
        %AuditEvent{}
        |> AuditEvent.changeset(%{
          actor_handle: actor_handle,
          action: "maintenance_sweep",
          result: :ok,
          metadata: summary
        })
        |> Repo.insert!()

      %{summary: summary, audit_event: audit_event}
    end)
    |> normalize_transaction_result()
  end

  def list_audit_events(limit \\ 20) when is_integer(limit) and limit > 0 do
    Repo.all(from event in AuditEvent, order_by: [desc: event.inserted_at], limit: ^limit)
  end

  def operator_handle?(handle) when is_binary(handle) do
    handle in operator_handles()
  end

  def operator_handle?(_handle), do: false

  defp operator_handles do
    Application.get_env(:mmgo, __MODULE__, [])[:handles] || []
  end

  defp count_active(module) do
    Repo.aggregate(from(record in module, where: record.status == :active), :count, :id)
  end

  defp count_status(module, status) do
    Repo.aggregate(from(record in module, where: record.status == ^status), :count, :id)
  end

  defp count_combat_active do
    Repo.aggregate(
      from(combat in Combat, where: combat.status in [:active_turn, :locked, :resolving]),
      :count,
      :id
    )
  end

  defp balance_total(owner_type) do
    Repo.aggregate(
      from(account in EconomyAccount, where: account.owner_type == ^owner_type),
      :sum,
      :current_balance
    ) || 0
  end

  defp count_ok(results) do
    Enum.count(results, fn
      {:ok, _result} -> true
      _other -> false
    end)
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp report_changeset(message) do
    %AuditEvent{}
    |> Changeset.change()
    |> Changeset.add_error(:action, message)
  end
end
