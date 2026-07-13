defmodule MMGO.Academy.ExamDeadlineWorker do
  @moduledoc """
  Resolves one persisted Academy exam attempt at its authoritative deadline.

  The worker names the term, phase, and attempt id so retries and stale jobs
  cannot touch a later exam phase or a newly opened attempt.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias MMGO.Academy

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"term_id" => term_id, "phase" => phase, "attempt_id" => attempt_id}
      }) do
    case Academy.expire_exam_attempt(term_id, phase, attempt_id) do
      {:ok, _term} ->
        :ok

      {:error, :exam_not_due} ->
        {:snooze, 1}

      {:error, :academy_exam_unavailable} ->
        :ok

      {:error, _reason} ->
        {:discard, :invalid_exam_attempt}
    end
  end
end
