defmodule MMGO.Spells.Creation do
  @moduledoc """
  Durable spell-creation rituals anchored to the continuously running world clock.

  An attempt exists before any seal validation or AI work. Its result remains
  sealed until the shared world clock reaches `completes_at`, so closing or
  reloading a client cannot shorten the ritual. Arena callers may select the
  server-only `:immediate?` policy; the same durable pipeline is retained, but
  its reveal deadline is the start instant instead of one world hour later.
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Repo
  alias MMGO.Spells.{CreationAttempt, RevealCreationAttemptWorker, ResolveCreationAttemptWorker}
  alias MMGO.Spells.{Spell, SpellFailure}
  alias MMGO.Travel.Clock

  @ritual_game_hours 1
  @circle_keys ~w(school actio forma vis tempus mutatio pretium base)
  @circle_atom_keys %{
    "school" => :school,
    "actio" => :actio,
    "forma" => :forma,
    "vis" => :vis,
    "tempus" => :tempus,
    "mutatio" => :mutatio,
    "pretium" => :pretium,
    "base" => :base
  }
  @max_circle_value_bytes 256
  @max_failure_reason_bytes 360
  @max_failure_formula_bytes 180
  @max_failure_marker_bytes 80
  @transport_errors [:timeout, :econnrefused, :nxdomain, :closed, :enetunreach]

  def begin(character, expected_location_id, raw_circle, opts \\ [])

  def begin(%Character{id: character_id}, expected_location_id, raw_circle, opts)
      when is_binary(character_id) and is_binary(expected_location_id) and is_list(opts) do
    result =
      Repo.transaction(fn ->
        character =
          Character
          |> where([character], character.id == ^character_id)
          |> lock("FOR UPDATE")
          |> Repo.one()

        if is_nil(character), do: Repo.rollback(:not_found)

        if character.current_location_id != expected_location_id do
          Repo.rollback(:location_changed)
        end

        if active_attempt_query(character.id) |> Repo.exists?() do
          Repo.rollback(:spell_creation_in_progress)
        end

        started_at = Keyword.get(opts, :now) || DateTime.utc_now()

        completes_at =
          if Keyword.get(opts, :immediate?, false) do
            started_at
          else
            DateTime.add(
              started_at,
              Clock.game_hours_to_real_seconds(@ritual_game_hours),
              :second
            )
          end

        attempt =
          %CreationAttempt{
            character_id: character.id,
            realm_id: character.realm_id,
            location_id: expected_location_id
          }
          |> CreationAttempt.changeset(%{
            status: :queued,
            input: sanitize_input(raw_circle),
            outcome: %{},
            started_at: started_at,
            completes_at: completes_at
          })
          |> Repo.insert!()

        resolve_job =
          %{"attempt_id" => attempt.id}
          |> ResolveCreationAttemptWorker.new()
          |> Oban.insert!()

        reveal_job =
          %{"attempt_id" => attempt.id}
          |> RevealCreationAttemptWorker.new(scheduled_at: completes_at)
          |> Oban.insert!()

        %{attempt: attempt, resolve_job: resolve_job, reveal_job: reveal_job}
      end)

    normalize_transaction_result(result)
  end

  def begin(_character, _expected_location_id, _raw_circle, _opts),
    do: {:error, :invalid_spell_circle}

  def active_attempt(character_id) when is_binary(character_id) do
    character_id
    |> active_attempt_query()
    |> order_by([attempt], desc: attempt.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def active_attempt(_character_id), do: nil

  def recent_attempt(character_id) when is_binary(character_id) do
    CreationAttempt
    |> where([attempt], attempt.character_id == ^character_id)
    |> order_by([attempt], desc: attempt.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> maybe_preload_spell()
  end

  def recent_attempt(_character_id), do: nil

  def get_attempt(attempt_id) when is_binary(attempt_id) do
    CreationAttempt
    |> Repo.get(attempt_id)
    |> maybe_preload_spell()
  end

  def get_attempt(_attempt_id), do: nil

  def claim_resolution(attempt_id) when is_binary(attempt_id) do
    result =
      Repo.transaction(fn ->
        attempt = lock_attempt(attempt_id)
        if is_nil(attempt), do: Repo.rollback(:not_found)

        case attempt.status do
          :queued ->
            updated_attempt =
              attempt
              |> CreationAttempt.changeset(%{status: :resolving})
              |> Repo.update!()
              |> Repo.preload(:spell, force: true)

            %{attempt: updated_attempt, action: :resolve}

          :resolving ->
            action = if attempt.spell, do: :recover_success, else: :resolve
            %{attempt: attempt, action: action}

          _sealed_or_revealed ->
            %{attempt: attempt, action: :noop}
        end
      end)

    normalize_transaction_result(result)
  end

  def claim_resolution(_attempt_id), do: {:error, :not_found}

  def finalize_success(attempt_id, opts \\ [])
      when is_binary(attempt_id) and is_list(opts) do
    finalize(attempt_id, :success, opts)
  end

  def finalize_failure(attempt_id, failure, opts \\ [])
      when is_binary(attempt_id) and is_list(opts) do
    finalize(attempt_id, {:failure, failure}, opts)
  end

  def reveal(attempt_id, opts \\ [])

  def reveal(attempt_id, opts) when is_binary(attempt_id) and is_list(opts) do
    now = Keyword.get(opts, :now) || DateTime.utc_now()

    result =
      Repo.transaction(fn ->
        attempt = lock_attempt(attempt_id)
        if is_nil(attempt), do: Repo.rollback(:not_found)

        cond do
          attempt.status == :revealed ->
            # Reveal delivery is intentionally at-least-once. A retried job
            # must still wake the spellbook if the original process died
            # after committing this status but before broadcasting it.
            %{attempt: attempt, broadcast?: true}

          attempt.status in [:queued, :resolving] ->
            Repo.rollback(:not_resolved)

          DateTime.compare(now, attempt.completes_at) == :lt ->
            Repo.rollback({:not_due, attempt.completes_at})

          true ->
            {outcome, resolved_at} =
              if displaced_success?(attempt) do
                if attempt.spell, do: Repo.delete!(attempt.spell)
                {failure_outcome(:spellbook_location), attempt.resolved_at || now}
              else
                {attempt.outcome, attempt.resolved_at}
              end

            revealed_attempt =
              attempt
              |> CreationAttempt.changeset(%{
                status: :revealed,
                outcome: outcome,
                resolved_at: resolved_at,
                revealed_at: now
              })
              |> Repo.update!()
              |> Repo.preload(:spell, force: true)

            %{attempt: revealed_attempt, broadcast?: true}
        end
      end)

    result
    |> normalize_transaction_result()
    |> maybe_broadcast_reveal()
  end

  def reveal(_attempt_id, _opts), do: {:error, :not_found}

  def character_topic(character_id) when is_binary(character_id),
    do: "spell_creation:character:#{character_id}"

  defp finalize(attempt_id, outcome, opts) do
    now = Keyword.get(opts, :now) || DateTime.utc_now()
    outcome_kind = outcome_kind(outcome)

    result =
      Repo.transaction(fn ->
        attempt = lock_attempt(attempt_id)
        if is_nil(attempt), do: Repo.rollback(:not_found)

        cond do
          attempt.status in [:sealed_success, :sealed_failure, :revealed] ->
            %{attempt: attempt, broadcast?: false}

          outcome_kind == :success and is_nil(attempt.spell) ->
            Repo.rollback(:spell_not_found)

          true ->
            revealed? = DateTime.compare(now, attempt.completes_at) != :lt

            outcome =
              if outcome_kind == :success and revealed? and displaced?(attempt) do
                {:failure, :spellbook_location}
              else
                outcome
              end

            outcome_kind = outcome_kind(outcome)

            if outcome_kind == :failure and attempt.spell do
              Repo.delete!(attempt.spell)
            end

            attrs = %{
              status: terminal_status(outcome_kind, revealed?),
              outcome: terminal_outcome(outcome, attempt.spell),
              resolved_at: now,
              revealed_at: if(revealed?, do: now, else: nil)
            }

            finalized_attempt =
              attempt
              |> CreationAttempt.changeset(attrs)
              |> Repo.update!()

            %{attempt: finalized_attempt, broadcast?: revealed?}
        end
      end)

    result
    |> normalize_transaction_result()
    |> maybe_broadcast_reveal()
  end

  defp terminal_status(_outcome_kind, true), do: :revealed
  defp terminal_status(:success, false), do: :sealed_success
  defp terminal_status(:failure, false), do: :sealed_failure

  defp outcome_kind(:success), do: :success
  defp outcome_kind({:failure, _failure}), do: :failure

  defp terminal_outcome(:success, %Spell{} = spell),
    do: %{"kind" => "success", "spell_id" => spell.id}

  defp terminal_outcome({:failure, failure}, _spell), do: failure_outcome(failure)

  defp failure_outcome(%SpellFailure{} = failure) do
    %{
      "kind" => "failure",
      "failure_kind" => "spell_rejected",
      "reason" => bounded_string(failure.reason, @max_failure_reason_bytes),
      "formula" => bounded_string(failure.formula, @max_failure_formula_bytes),
      "school" => bounded_string(failure.school, 24),
      "instability_markers" => bounded_string_list(failure.instability_markers, 12),
      "provider_status" => provider_request_status(failure)
    }
    |> reject_nil_values()
  end

  defp failure_outcome(%Changeset{} = changeset) do
    fields =
      changeset
      |> Changeset.traverse_errors(fn {_message, _opts} -> :invalid end)
      |> validation_error_paths()

    %{"kind" => "failure", "failure_kind" => "validation", "fields" => fields}
  end

  defp failure_outcome(%Req.TransportError{}) do
    %{"kind" => "failure", "failure_kind" => "transport_error"}
  end

  defp failure_outcome(%Jason.DecodeError{}) do
    %{"kind" => "failure", "failure_kind" => "invalid_provider_response"}
  end

  defp failure_outcome({provider, status, _details})
       when provider in [:deepseek_api, :gemini_api] and is_integer(status) do
    %{
      "kind" => "failure",
      "failure_kind" => "provider_error",
      "provider_status" => status
    }
  end

  defp failure_outcome(:missing_api_key) do
    %{
      "kind" => "failure",
      "failure_kind" => "provider_configuration",
      "code" => "missing_api_key"
    }
  end

  defp failure_outcome(reason) when reason in [:empty_response, :invalid_response] do
    %{
      "kind" => "failure",
      "failure_kind" => "invalid_provider_response",
      "code" => Atom.to_string(reason)
    }
  end

  defp failure_outcome(reason) when reason in @transport_errors do
    %{
      "kind" => "failure",
      "failure_kind" => "transport_error",
      "code" => Atom.to_string(reason)
    }
  end

  defp failure_outcome(reason) when is_atom(reason) do
    %{
      "kind" => "failure",
      "failure_kind" => "user_error",
      "code" => Atom.to_string(reason)
    }
  end

  defp failure_outcome(_reason) do
    %{"kind" => "failure", "failure_kind" => "technical"}
  end

  defp validation_error_paths(errors), do: validation_error_paths(errors, nil)

  defp validation_error_paths(errors, prefix) when is_map(errors) do
    errors
    |> Enum.flat_map(fn {field, nested} ->
      path = Enum.reject([prefix, to_string(field)], &is_nil/1) |> Enum.join(".")
      validation_error_paths(nested, path)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp validation_error_paths(errors, prefix) when is_list(errors) do
    if Enum.all?(errors, &is_atom/1) do
      [prefix]
    else
      errors
      |> Enum.with_index()
      |> Enum.flat_map(fn {nested, index} ->
        validation_error_paths(nested, "#{prefix}.#{index}")
      end)
    end
  end

  defp validation_error_paths(_errors, prefix), do: [prefix]

  defp provider_request_status(%{ai_request: %{status: status}})
       when status in [:succeeded, :failed],
       do: Atom.to_string(status)

  defp provider_request_status(_failure), do: nil

  defp sanitize_input(raw_circle) when is_map(raw_circle) do
    Enum.reduce_while(@circle_keys, %{}, fn key, circle ->
      case fetch_circle_value(raw_circle, key) do
        :missing ->
          {:cont, circle}

        {:ok, value}
        when is_binary(value) and byte_size(value) <= @max_circle_value_bytes ->
          if String.valid?(value) do
            {:cont, Map.put(circle, key, value)}
          else
            {:halt, :invalid}
          end

        _invalid ->
          {:halt, :invalid}
      end
    end)
    |> case do
      :invalid -> %{"invalid_payload" => true}
      circle -> %{"circle" => circle}
    end
  end

  defp sanitize_input(_raw_circle), do: %{"invalid_payload" => true}

  defp fetch_circle_value(raw_circle, key) do
    case Map.fetch(raw_circle, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        case Map.fetch(raw_circle, Map.fetch!(@circle_atom_keys, key)) do
          {:ok, value} -> {:ok, value}
          :error -> :missing
        end
    end
  end

  defp active_attempt_query(character_id) do
    from attempt in CreationAttempt,
      where: attempt.character_id == ^character_id and attempt.status != :revealed
  end

  defp lock_attempt(attempt_id) do
    CreationAttempt
    |> where([attempt], attempt.id == ^attempt_id)
    |> lock("FOR UPDATE")
    |> preload(:spell)
    |> Repo.one()
  end

  defp maybe_preload_spell(nil), do: nil
  defp maybe_preload_spell(attempt), do: Repo.preload(attempt, :spell)

  defp displaced_success?(%CreationAttempt{status: :sealed_success} = attempt) do
    displaced?(attempt)
  end

  defp displaced_success?(_attempt), do: false

  defp displaced?(attempt) do
    current_location_id =
      Character
      |> where([character], character.id == ^attempt.character_id)
      |> select([character], character.current_location_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    current_location_id != attempt.location_id
  end

  defp maybe_broadcast_reveal({:ok, %{attempt: attempt, broadcast?: broadcast?}}) do
    if broadcast? do
      Phoenix.PubSub.broadcast(
        MMGO.PubSub,
        character_topic(attempt.character_id),
        {:spell_creation_revealed, attempt.id}
      )
    end

    {:ok, attempt}
  end

  defp maybe_broadcast_reveal({:error, _reason} = error), do: error

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}

  defp bounded_string(value, max_bytes) when is_binary(value) do
    if String.valid?(value) and byte_size(value) <= max_bytes, do: value, else: nil
  end

  defp bounded_string(_value, _max_bytes), do: nil

  defp bounded_string_list(values, max_items) when is_list(values) do
    values
    |> Enum.take(max_items)
    |> Enum.reduce([], fn value, acc ->
      case bounded_string(value, @max_failure_marker_bytes) do
        nil -> acc
        bounded -> [bounded | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp bounded_string_list(_values, _max_items), do: []

  defp reject_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
