defmodule MMGO.Scavenging do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Inventory
  alias MMGO.Parties
  alias MMGO.Repo
  alias MMGO.Scavenging.{Attempt, CompleteAttemptWorker, ResourceCache}
  alias MMGO.Travel
  alias MMGO.Travel.Clock
  alias MMGO.Worlds.Location

  def list_resource_caches(location_id) when is_binary(location_id) do
    Repo.all(
      from resource_cache in ResourceCache,
        where: resource_cache.location_id == ^location_id,
        order_by: [asc: resource_cache.inserted_at],
        preload: [:item_template]
    )
  end

  def available_resource_caches(location_id) when is_binary(location_id) do
    location_id
    |> list_resource_caches()
    |> Enum.map(&refresh_resource_cache_if_due/1)
    |> Enum.filter(&(&1.status == :available and &1.quantity_remaining > 0))
  end

  def get_resource_cache!(id) do
    ResourceCache
    |> Repo.get!(id)
    |> Repo.preload(:item_template)
  end

  def active_attempt(character_id) when is_binary(character_id) do
    Repo.get_by(Attempt, character_id: character_id, status: :active)
  end

  def list_attempts_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from attempt in Attempt,
        where: attempt.character_id == ^character_id,
        order_by: [desc: attempt.inserted_at],
        preload: [:resource_cache, :location]
    )
  end

  def ensure_resource_cache(%Location{} = location, attrs \\ %{}) do
    attrs = stringify_keys(attrs)
    resource_code = attrs["resource_code"] || default_resource_code(location.kind)

    case Repo.get_by(ResourceCache, location_id: location.id, resource_code: resource_code) do
      %ResourceCache{} = resource_cache ->
        {:ok, Repo.preload(resource_cache, :item_template)}

      nil ->
        %ResourceCache{}
        |> ResourceCache.changeset(
          default_resource_attrs(location)
          |> Map.merge(attrs)
          |> Map.merge(%{
            "realm_id" => location.realm_id,
            "location_id" => location.id,
            "resource_code" => resource_code
          })
        )
        |> Repo.insert()
        |> case do
          {:ok, resource_cache} -> {:ok, Repo.preload(resource_cache, :item_template)}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  def start_attempt(
        %Character{} = character,
        %ResourceCache{} = resource_cache,
        quantity,
        opts \\ []
      )
      when is_integer(quantity) do
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())

    duration_game_days =
      Keyword.get(opts, :duration_game_days, default_duration_game_days(quantity))

    Repo.transaction(fn ->
      character = lock_character!(character.id)
      resource_cache = lock_resource_cache!(resource_cache.id)

      validate_attempt_start!(character, resource_cache, quantity)

      completes_at = Clock.arrival_at(started_at, duration_game_days)
      remaining_quantity = resource_cache.quantity_remaining - quantity

      updated_resource_cache =
        resource_cache
        |> ResourceCache.changeset(%{
          quantity_remaining: remaining_quantity,
          status: next_cache_status(resource_cache, remaining_quantity),
          respawn_at: next_respawn_at(resource_cache, remaining_quantity, started_at)
        })
        |> Repo.update!()

      attempt =
        %Attempt{}
        |> Attempt.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          location_id: resource_cache.location_id,
          resource_cache_id: resource_cache.id,
          status: :active,
          quantity_requested: quantity,
          quantity_yielded: 0,
          started_at: started_at,
          completes_at: completes_at,
          metadata: %{"duration_game_days" => duration_game_days}
        })
        |> Repo.insert!()

      job =
        %{"attempt_id" => attempt.id}
        |> CompleteAttemptWorker.new(
          schedule_in: max(DateTime.diff(completes_at, DateTime.utc_now(), :second), 0)
        )
        |> Oban.insert!()

      %{attempt: preload_attempt(attempt), resource_cache: updated_resource_cache, job: job}
    end)
    |> normalize_transaction_result()
  end

  def complete_attempt_by_id(attempt_id, opts \\ []) when is_binary(attempt_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force, false)

    Repo.transaction(fn ->
      attempt = lock_attempt!(attempt_id)
      character = lock_character!(attempt.character_id)
      resource_cache = get_resource_cache!(attempt.resource_cache_id)

      cond do
        attempt.status != :active ->
          Repo.rollback(attempt_changeset("attempt is not active"))

        not force? and DateTime.compare(now, attempt.completes_at) == :lt ->
          Repo.rollback(attempt_changeset("attempt is not due yet"))

        true ->
          reward_result =
            case resource_cache.item_template do
              nil ->
                {:ok,
                 %{
                   resource_code: resource_cache.resource_code,
                   quantity: attempt.quantity_requested
                 }}

              item_template ->
                Inventory.grant_item(character, item_template, %{
                  quantity: attempt.quantity_requested
                })
            end

          case reward_result do
            {:ok, reward} ->
              updated_character =
                character
                |> Character.changeset(%{xp: character.xp + scavenging_xp(attempt)})
                |> Repo.update!()

              updated_attempt =
                attempt
                |> Attempt.changeset(%{
                  status: :completed,
                  quantity_yielded: attempt.quantity_requested,
                  completed_at: now,
                  metadata: Map.put(attempt.metadata || %{}, "xp_awarded", scavenging_xp(attempt))
                })
                |> Repo.update!()

              %{
                attempt: preload_attempt(updated_attempt),
                character: updated_character,
                reward: reward
              }

            {:error, %Changeset{} = changeset} ->
              Repo.rollback(changeset)
          end
      end
    end)
    |> normalize_transaction_result()
  end

  def refresh_resource_cache_if_due(%ResourceCache{} = resource_cache, now \\ DateTime.utc_now()) do
    if (resource_cache.status == :respawning and resource_cache.respawn_at) &&
         DateTime.compare(now, resource_cache.respawn_at) != :lt do
      resource_cache
      |> ResourceCache.changeset(%{
        quantity_remaining: resource_cache.quantity_total,
        status: :available,
        respawn_at: nil
      })
      |> Repo.update!()
      |> Repo.preload(:item_template)
    else
      resource_cache
    end
  end

  def refresh_due_resource_caches(now \\ DateTime.utc_now()) do
    ResourceCache
    |> where(
      [resource_cache],
      resource_cache.status == :respawning and resource_cache.respawn_at <= ^now
    )
    |> Repo.all()
    |> Enum.map(&refresh_resource_cache_if_due(&1, now))
  end

  defp validate_attempt_start!(
         %Character{} = character,
         %ResourceCache{} = resource_cache,
         quantity
       ) do
    cond do
      quantity <= 0 ->
        Repo.rollback(resource_changeset("quantity must be greater than zero"))

      character.realm_id != resource_cache.realm_id ->
        Repo.rollback(
          resource_changeset("character must belong to the same realm as the resource cache")
        )

      character.current_location_id != resource_cache.location_id ->
        Repo.rollback(
          resource_changeset("character must be at the resource location to scavenge")
        )

      resource_cache.status != :available ->
        Repo.rollback(resource_changeset("resource cache is not available"))

      quantity > resource_cache.quantity_remaining ->
        Repo.rollback(resource_changeset("quantity exceeds the remaining resources"))

      active_attempt(character.id) ->
        Repo.rollback(attempt_changeset("character already has an active scavenging attempt"))

      Travel.active_journey(character.id) ->
        Repo.rollback(attempt_changeset("character cannot scavenge while travelling"))

      Parties.active_expedition_for_character(character.id) ->
        Repo.rollback(attempt_changeset("character cannot scavenge while on an expedition"))

      true ->
        :ok
    end
  end

  defp preload_attempt(%Attempt{} = attempt) do
    Repo.preload(attempt, [:location, resource_cache: :item_template])
  end

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_resource_cache!(resource_cache_id) do
    ResourceCache
    |> where([resource_cache], resource_cache.id == ^resource_cache_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload(:item_template)
  end

  defp lock_attempt!(attempt_id) do
    Attempt
    |> where([attempt], attempt.id == ^attempt_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> preload_attempt()
  end

  defp default_resource_attrs(%Location{} = location) do
    case location.kind do
      :wilderness ->
        %{"quantity_total" => 3, "quantity_remaining" => 3, "respawn_game_days" => 28}

      :tower ->
        %{"quantity_total" => 2, "quantity_remaining" => 2, "respawn_game_days" => 56}

      :base ->
        %{"quantity_total" => 1, "quantity_remaining" => 1, "respawn_game_days" => 14}

      _other ->
        %{"quantity_total" => 1, "quantity_remaining" => 1, "respawn_game_days" => 28}
    end
  end

  defp default_resource_code(:wilderness), do: "forage"
  defp default_resource_code(:tower), do: "arcane_debris"
  defp default_resource_code(:base), do: "workshop_scraps"
  defp default_resource_code(_kind), do: "salvage"

  defp default_duration_game_days(quantity), do: max(quantity, 1)

  defp next_cache_status(%ResourceCache{respawn_game_days: respawn_game_days}, 0)
       when respawn_game_days > 0,
       do: :respawning

  defp next_cache_status(_resource_cache, 0), do: :depleted
  defp next_cache_status(_resource_cache, _remaining_quantity), do: :available

  defp next_respawn_at(%ResourceCache{respawn_game_days: respawn_game_days}, 0, started_at)
       when respawn_game_days > 0,
       do: Clock.arrival_at(started_at, respawn_game_days)

  defp next_respawn_at(_resource_cache, _remaining_quantity, _started_at), do: nil

  defp scavenging_xp(%Attempt{} = attempt) do
    max(attempt.quantity_requested * 3, 1)
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp resource_changeset(message) do
    %ResourceCache{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp attempt_changeset(message) do
    %Attempt{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
