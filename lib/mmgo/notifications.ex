defmodule MMGO.Notifications do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.{Character, TelegramIdentity}
  alias MMGO.Notifications.{DeliveryWorker, Formatter, Notification}
  alias MMGO.Repo

  @channels [:telegram]
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
    enqueue(
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
    enqueue(
      character,
      :academy_completed,
      %{
        enrollment_id: enrollment.id,
        program_type: to_string(enrollment.program_type),
        track: enrollment.track && to_string(enrollment.track)
      },
      dedupe_key: "academy-completed:#{enrollment.id}"
    )
  end

  def notify_scavenge_completed(%Character{} = character, attempt) do
    enqueue(
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

  def notify_brew_completed(%Character{} = character, brew_job) do
    enqueue(
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
    enqueue(
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
    enqueue(
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
    enqueue(
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
    enqueue(
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
    enqueue(
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
    enqueue(
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
    enqueue(
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
    enqueue(
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

  def notify_org_invitation(%Character{} = character, invitation, organization) do
    enqueue(
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
