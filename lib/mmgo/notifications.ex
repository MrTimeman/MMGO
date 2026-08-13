defmodule MMGO.Notifications do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.{Character, TelegramIdentity}
  alias MMGO.Notifications.{DeliveryWorker, Formatter, Notification}
  alias MMGO.Repo

  @channels [:in_app, :telegram]
  def list_notifications(character_id \\ nil) do
    query =
      case character_id do
        nil ->
          Notification

        character_id ->
          from notification in Notification, where: notification.character_id == ^character_id
      end

    Repo.all(from notification in query, order_by: [desc: notification.inserted_at])
  end

  def get_notification!(id), do: Repo.get!(Notification, id)

  def list_unread_notifications(character_id) when is_binary(character_id) do
    Notification
    |> where(
      [notification],
      notification.character_id == ^character_id and notification.channel == :in_app and
        is_nil(notification.read_at)
    )
    |> order_by([notification], desc: notification.inserted_at)
    |> Repo.all()
  end

  def list_unread_notifications(_character_id), do: []

  def mark_all_read(character_id) when is_binary(character_id) do
    {count, _rows} =
      Notification
      |> where(
        [notification],
        notification.character_id == ^character_id and is_nil(notification.read_at)
      )
      |> Repo.update_all(set: [read_at: DateTime.utc_now()])

    {:ok, count}
  end

  def mark_all_read(_character_id), do: {:error, :invalid_character}

  def delete_read_notifications(character_id) when is_binary(character_id) do
    {count, _rows} =
      Notification
      |> where(
        [notification],
        notification.character_id == ^character_id and not is_nil(notification.read_at) and
          notification.status != :pending
      )
      |> Repo.delete_all()

    {:ok, count}
  end

  def delete_read_notifications(_character_id), do: {:error, :invalid_character}

  def enqueue(%Character{} = character, kind, payload, opts \\ []) when is_map(payload) do
    channel = Keyword.get(opts, :channel, :telegram)
    scheduled_at = Keyword.get(opts, :scheduled_at, DateTime.utc_now())
    metadata = Keyword.get(opts, :metadata, %{})
    dedupe_key = Keyword.get(opts, :dedupe_key)

    with :ok <- validate_channel(channel),
         {:ok, identity} <- telegram_identity_for_character(character.id, channel),
         :ok <- validate_dedupe_key(character.id, dedupe_key) do
      notification_attrs = %{
        character_id: character.id,
        channel: channel,
        kind: to_string(kind),
        status: :pending,
        scheduled_at: scheduled_at,
        payload: stringify_keys(payload),
        metadata: metadata_with_chat(metadata, identity.telegram_user_id),
        dedupe_key: dedupe_key
      }

      %Notification{}
      |> Notification.changeset(notification_attrs)
      |> Repo.insert()
      |> case do
        {:ok, notification} ->
          schedule_delivery(notification)
          {:ok, notification}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc "Stores an immediately visible in-app notification without requiring Telegram identity."
  def enqueue_in_app(%Character{} = character, kind, payload, opts \\ []) when is_map(payload) do
    scheduled_at = Keyword.get(opts, :scheduled_at, DateTime.utc_now())
    delivered_at = Keyword.get(opts, :delivered_at, scheduled_at)
    metadata = Keyword.get(opts, :metadata, %{})
    dedupe_key = Keyword.get(opts, :dedupe_key)

    with :ok <- validate_channel(:in_app),
         :ok <- validate_dedupe_key(character.id, dedupe_key) do
      %Notification{}
      |> Notification.changeset(%{
        character_id: character.id,
        channel: :in_app,
        kind: to_string(kind),
        status: :sent,
        scheduled_at: scheduled_at,
        delivered_at: delivered_at,
        payload: stringify_keys(payload),
        metadata: stringify_keys(metadata),
        dedupe_key: dedupe_key
      })
      |> Repo.insert()
    end
  end

  def deliver_notification_by_id(notification_id, opts \\ [])
      when is_binary(notification_id) and is_list(opts) do
    mark_failed? = Keyword.get(opts, :mark_failed?, true)

    Repo.transaction(fn ->
      notification =
        Notification
        |> where([notification], notification.id == ^notification_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(notification) do
        Repo.rollback(notification_changeset("notification could not be found"))
      end

      if notification.status != :pending do
        Repo.rollback(notification_changeset("notification is not pending"))
      end

      if DateTime.compare(DateTime.utc_now(), notification.scheduled_at) == :lt do
        Repo.rollback(notification_changeset("notification is not due yet"))
      end

      with {:ok, chat_id} <- chat_id(notification),
           {:ok, %{text: text, opts: opts}} <- Formatter.render(notification),
           {:ok, _response} <- MMGO.Telegram.send_message(chat_id, text, opts) do
        notification
        |> Notification.changeset(%{status: :sent, delivered_at: DateTime.utc_now()})
        |> Repo.update!()
      else
        {:error, reason} ->
          handle_delivery_failure(notification, reason, mark_failed?)
      end
    end)
    |> normalize_delivery_result()
  end

  def notify_journey_arrived(%Character{} = character, journey) do
    notify(
      character,
      :journey_arrived,
      %{
        journey_id: journey.id,
        to_location_id: journey.to_location_id,
        status: to_string(journey.status)
      },
      dedupe_key: "journey-arrived:#{journey.id}"
    )
  end

  def notify_enrollment_completed(%Character{} = character, enrollment) do
    notify(
      character,
      :academy_completed,
      %{
        enrollment_id: enrollment.id,
        program_type: to_string(enrollment.program_type),
        track: enrollment.track && to_string(enrollment.track),
        status: to_string(enrollment.status),
        outcome_tier: Map.get(enrollment.metadata || %{}, "outcome_tier")
      },
      dedupe_key: "academy-completed:#{enrollment.id}"
    )
  end

  def notify_scavenge_completed(%Character{} = character, attempt) do
    notify(
      character,
      :scavenge_completed,
      %{
        attempt_id: attempt.id,
        resource_cache_id: attempt.resource_cache_id,
        quantity_yielded: attempt.quantity_yielded
      },
      dedupe_key: "scavenge-completed:#{attempt.id}"
    )
  end

  @doc """
  Tells a player they have finished an arena quest.

  Deduped on the quest and the period it belongs to, so a quest announces itself
  exactly once however many times the match settles.
  """
  def notify_arena_quest_completed(%Character{} = character, quest, period_key \\ nil) do
    notify(
      character,
      :arena_quest_completed,
      %{
        code: quest.code,
        name: quest.name,
        period: to_string(quest.period),
        reward_xp: quest.reward_xp
      },
      dedupe_key: "arena-quest:#{quest.code}:#{period_key || Date.utc_today()}"
    )
  end

  def notify_brew_completed(%Character{} = character, brew_job) do
    notify(
      character,
      :brew_completed,
      %{
        brew_job_id: brew_job.id,
        recipe_id: brew_job.recipe_id,
        yielded_quantity: brew_job.yielded_quantity
      },
      dedupe_key: "brew-completed:#{brew_job.id}"
    )
  end

  def notify_craft_completed(%Character{} = character, craft_job) do
    notify(
      character,
      :craft_completed,
      %{
        craft_job_id: craft_job.id,
        recipe_id: craft_job.recipe_id,
        yielded_quantity: craft_job.yielded_quantity
      },
      dedupe_key: "craft-completed:#{craft_job.id}"
    )
  end

  def notify_research_completed(%Character{} = character, project) do
    notify(
      character,
      :research_completed,
      %{
        project_id: project.id,
        project_kind: to_string(project.project_kind),
        title: project.title
      },
      dedupe_key: "research-completed:#{project.id}"
    )
  end

  def notify_base_ready(%Character{} = character, base) do
    notify(
      character,
      :base_ready,
      %{
        base_id: base.id,
        location_id: base.location_id,
        kind: to_string(base.kind)
      },
      dedupe_key: "base-ready:#{base.id}"
    )
  end

  def notify_realm_migration_started(%Character{} = character, migration, destination_realm) do
    notify(
      character,
      :realm_migration_started,
      %{
        migration_id: migration.id,
        destination_realm_id: destination_realm.id,
        destination_realm_name: destination_realm.name,
        freeze_ends_at: migration.freeze_ends_at && DateTime.to_iso8601(migration.freeze_ends_at)
      },
      dedupe_key: "realm-migration-started:#{migration.id}"
    )
  end

  def notify_realm_migration_completed(%Character{} = character, migration) do
    notify(
      character,
      :realm_migration_completed,
      %{
        migration_id: migration.id,
        passive_xp_awarded: migration.passive_xp_awarded
      },
      dedupe_key: "realm-migration-completed:#{migration.id}"
    )
  end

  def notify_extraction_completed(%Character{} = character, run, extraction_type) do
    notify(
      character,
      :dungeon_extraction_completed,
      %{
        run_id: run.id,
        extraction_type: to_string(extraction_type),
        status: to_string(run.status)
      },
      dedupe_key: "dungeon-extraction-completed:#{run.id}:#{extraction_type}"
    )
  end

  def notify_run_failed(%Character{} = character, run, lost_item_count) do
    notify(
      character,
      :dungeon_run_failed,
      %{
        run_id: run.id,
        lost_item_count: lost_item_count
      },
      dedupe_key: "dungeon-run-failed:#{run.id}:#{character.id}"
    )
  end

  def notify_club_invitation(%Character{} = character, invitation, club) do
    notify(
      character,
      :club_invitation,
      %{
        invitation_id: invitation.id,
        club_id: club.id,
        club_name: club.name,
        club_type: to_string(club.club_type)
      },
      dedupe_key: "club-invitation:#{invitation.id}"
    )
  end

  def notify_party_invitation(%Character{} = character, invitation, party) do
    notify(
      character,
      :party_invitation,
      %{
        invitation_id: invitation["id"],
        party_id: party.id,
        party_name: party.name
      },
      dedupe_key: "party-invitation:#{invitation["id"]}"
    )
  end

  def notify_org_invitation(%Character{} = character, invitation, organization) do
    notify(
      character,
      :organization_invitation,
      %{
        invitation_id: invitation.id,
        organization_id: organization.id,
        organization_name: organization.name,
        organization_kind: to_string(organization.kind)
      },
      dedupe_key: "organization-invitation:#{invitation.id}"
    )
  end

  @doc "Notifies the target of a consent-based request to exchange Telegram contacts."
  def notify_overworld_contact_request(
        %Character{} = target,
        %{id: encounter_id},
        %Character{} = requester
      ) do
    notify(
      target,
      :overworld_contact_request,
      %{
        encounter_id: encounter_id,
        requester_name: requester.name
      },
      dedupe_key: "overworld-contact-request:#{encounter_id}"
    )
  end

  @doc "Notifies one consenting traveler of the other traveler's public Telegram username."
  def notify_overworld_contact_accepted(
        %Character{} = recipient,
        %{id: encounter_id},
        %Character{} = counterpart
      ) do
    recipient_username = telegram_username_for_character(recipient.id)
    counterpart_username = telegram_username_for_character(counterpart.id)

    notify(
      recipient,
      :overworld_contact_accepted,
      %{
        encounter_id: encounter_id,
        counterpart_name: counterpart.name,
        telegram_username:
          if(is_binary(recipient_username) and is_binary(counterpart_username),
            do: counterpart_username
          )
      },
      dedupe_key: "overworld-contact-accepted:#{encounter_id}"
    )
  end

  @doc "Notifies the requester that a Telegram contact exchange was declined."
  def notify_overworld_contact_rejected(
        %Character{} = recipient,
        %{id: encounter_id} = encounter,
        %Character{} = counterpart
      ) do
    notify(
      recipient,
      :overworld_contact_rejected,
      %{
        encounter_id: encounter_id,
        counterpart_name: counterpart.name,
        decision: contact_decision(encounter)
      },
      dedupe_key: "overworld-contact-rejected:#{encounter_id}"
    )
  end

  defp notify(%Character{} = character, kind, payload, opts) do
    dedupe_key = Keyword.get(opts, :dedupe_key)
    in_app_opts = Keyword.put(opts, :dedupe_key, channel_dedupe_key(dedupe_key, :in_app))
    telegram_opts = Keyword.put(opts, :dedupe_key, channel_dedupe_key(dedupe_key, :telegram))

    case enqueue_in_app(character, kind, payload, in_app_opts) do
      {:ok, in_app_notification} ->
        _ = enqueue(character, kind, payload, telegram_opts)
        {:ok, in_app_notification}

      {:error, _reason} = error ->
        error
    end
  end

  defp channel_dedupe_key(nil, _channel), do: nil
  defp channel_dedupe_key(dedupe_key, channel), do: "#{dedupe_key}:#{channel}"

  defp validate_channel(channel) when channel in @channels, do: :ok

  defp validate_channel(_channel),
    do: {:error, notification_changeset("notification channel is invalid")}

  defp validate_dedupe_key(_character_id, nil), do: :ok

  defp validate_dedupe_key(character_id, dedupe_key) do
    if Repo.exists?(
         from notification in Notification,
           where:
             notification.character_id == ^character_id and notification.dedupe_key == ^dedupe_key
       ) do
      {:error, notification_changeset("notification has already been queued")}
    else
      :ok
    end
  end

  defp telegram_identity_for_character(character_id, :telegram) do
    query =
      from identity in TelegramIdentity,
        join: account in assoc(identity, :account),
        join: character in Character,
        on: character.account_id == account.id,
        where: character.id == ^character_id,
        select: identity

    case Repo.one(query) do
      %TelegramIdentity{} = identity -> {:ok, identity}
      nil -> {:error, notification_changeset("character has no Telegram identity")}
    end
  end

  defp telegram_username_for_character(character_id) do
    from(identity in TelegramIdentity,
      join: account in assoc(identity, :account),
      join: character in Character,
      on: character.account_id == account.id,
      where: character.id == ^character_id,
      select: identity.telegram_username
    )
    |> Repo.one()
    |> normalize_telegram_username()
  end

  defp normalize_telegram_username(username) when is_binary(username) do
    username
    |> String.trim()
    |> String.trim_leading("@")
    |> case do
      "" -> nil
      username -> username
    end
  end

  defp normalize_telegram_username(_username), do: nil

  defp contact_decision(%{metadata: metadata}) when is_map(metadata),
    do: Map.get(metadata, "contact_decision", "decline")

  defp contact_decision(_encounter), do: "decline"

  defp schedule_delivery(%Notification{} = notification) do
    delay = max(DateTime.diff(notification.scheduled_at, DateTime.utc_now(), :second), 0)

    %{"notification_id" => notification.id}
    |> DeliveryWorker.new(schedule_in: delay)
    |> Oban.insert()
  end

  defp metadata_with_chat(metadata, chat_id) do
    stringify_keys(metadata)
    |> Map.put_new("telegram_chat_id", chat_id)
  end

  defp chat_id(%Notification{} = notification) do
    case notification.metadata["telegram_chat_id"] do
      chat_id when is_integer(chat_id) ->
        {:ok, chat_id}

      chat_id when is_binary(chat_id) ->
        case Integer.parse(chat_id) do
          {parsed, ""} -> {:ok, parsed}
          _ -> {:error, :invalid_chat_id}
        end

      _ ->
        {:error, :missing_chat_id}
    end
  end

  defp handle_delivery_failure(%Notification{} = notification, reason, true) do
    updated_notification =
      notification
      |> Notification.changeset(%{status: :failed, error: inspect(reason)})
      |> Repo.update!()

    {:delivery_failed, updated_notification}
  end

  defp handle_delivery_failure(%Notification{}, reason, false) do
    {:retryable_delivery_failed, reason}
  end

  defp normalize_delivery_result({:ok, {:delivery_failed, notification}}),
    do: {:error, notification}

  defp normalize_delivery_result({:ok, {:retryable_delivery_failed, reason}}),
    do: {:error, {:retryable, reason}}

  defp normalize_delivery_result({:ok, notification}), do: {:ok, notification}

  defp normalize_delivery_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_delivery_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp notification_changeset(message) do
    %Notification{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
