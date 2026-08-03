defmodule MMGO.Spells.ResolveCreationAttemptWorker do
  @moduledoc "Resolves a persisted spell ritual independently from its LiveView."

  use Oban.Worker,
    queue: :default,
    max_attempts: 20,
    unique: [period: :infinity, fields: [:worker, :args]]

  alias MMGO.Play

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_id" => attempt_id}}) do
    case Play.resolve_spell_creation_attempt(attempt_id) do
      :ok -> :ok
      {:ok, _result} -> :ok
      {:error, :not_found} -> {:discard, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
