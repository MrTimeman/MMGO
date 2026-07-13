defmodule MMGO.Academy.ExamDeadlineWorkerTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Academy
  alias MMGO.Academy.{ExamDeadlineWorker, Term}
  alias MMGO.Repo
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "exam-deadline", name: "Exam Deadline Realm", is_default: true})

    character = character_fixture(realm, "exam-deadline-student", "Exam Deadline Student")
    term = academy_core_term_ready_for_midterm(character)

    %{realm: realm, character: character, term: term}
  end

  test "opening an exam persists one deadline across a reconnect", %{
    character: character,
    term: term
  } do
    now = DateTime.utc_now()

    assert {:ok, first} = Academy.start_exam_attempt(character.id, term.id, now: now)

    assert {:ok, resumed} =
             Academy.start_exam_attempt(character.id, term.id,
               now: DateTime.add(now, 20, :second)
             )

    assert first.resumed? == false
    assert resumed.resumed?
    assert resumed.attempt_id == first.attempt_id
    assert resumed.deadline_at == first.deadline_at
    assert first.deadline_at == DateTime.add(now, Academy.exam_duration_seconds(), :second)
    assert first.deadline_worker.args["attempt_id"] == first.attempt_id

    persisted = Repo.get!(Term, term.id).metadata["exam_attempt"]
    assert persisted["id"] == first.attempt_id
    assert persisted["deadline_at"] == DateTime.to_iso8601(first.deadline_at)
    assert persisted["status"] == "open"
  end

  test "a timed submission is accepted before, but never at, its persisted deadline", %{
    character: character,
    term: term
  } do
    now = ~U[2026-07-13 10:00:00Z]
    assert {:ok, attempt} = Academy.start_exam_attempt(character.id, term.id, now: now)

    assert {:ok, submitted} =
             Academy.submit_exam_attempt(
               character.id,
               term.id,
               :midterm,
               90,
               now: DateTime.add(now, 299, :second)
             )

    assert Academy.term_progress(submitted).phase == :final
    assert submitted.metadata["exam_attempt"]["status"] == "submitted"
    assert submitted.metadata["exam_attempt"]["id"] == attempt.attempt_id

    final_term = Repo.get!(Term, term.id)
    assert {:ok, final_attempt} = Academy.start_exam_attempt(character.id, term.id, now: now)

    assert {:error, :academy_exam_expired} =
             Academy.submit_exam_attempt(
               character.id,
               final_term.id,
               :final,
               100,
               now: final_attempt.deadline_at
             )

    assert Repo.get!(Term, term.id).status == :active
  end

  test "a due worker fails a required midterm once and stale retries are harmless", %{
    character: character,
    term: term
  } do
    now = DateTime.add(DateTime.utc_now(), -(Academy.exam_duration_seconds() + 1), :second)
    assert {:ok, attempt} = Academy.start_exam_attempt(character.id, term.id, now: now)

    assert :ok = ExamDeadlineWorker.perform(attempt.deadline_worker)

    failed = Repo.get!(Term, term.id)
    assert failed.status == :failed
    assert failed.metadata["failure_reason"] == "exam_timeout"
    assert failed.metadata["exam_timeout_phase"] == "midterm"
    assert failed.metadata["exam_attempt"]["status"] == "expired"

    assert :ok = ExamDeadlineWorker.perform(attempt.deadline_worker)
    assert Repo.get!(Term, term.id).status == :failed
  end

  test "an early worker snoozes without changing an open exam", %{
    character: character,
    term: term
  } do
    assert {:ok, future_attempt} = Academy.start_exam_attempt(character.id, term.id)
    assert {:snooze, 1} = ExamDeadlineWorker.perform(future_attempt.deadline_worker)
    assert Repo.get!(Term, term.id).status == :active
  end

  test "a stale midterm worker cannot resolve the later final attempt", %{
    character: character,
    term: term
  } do
    past = DateTime.add(DateTime.utc_now(), -(Academy.exam_duration_seconds() + 1), :second)

    assert {:ok, first_attempt} = Academy.start_exam_attempt(character.id, term.id, now: past)

    assert {:ok, _midterm} =
             Academy.submit_exam_attempt(
               character.id,
               term.id,
               :midterm,
               95,
               now: DateTime.add(past, Academy.exam_duration_seconds() - 1, :second)
             )

    assert {:ok, final_attempt} =
             Academy.start_exam_attempt(
               character.id,
               term.id,
               now: DateTime.add(past, Academy.exam_duration_seconds() - 1, :second)
             )

    assert :ok = ExamDeadlineWorker.perform(first_attempt.deadline_worker)

    current = Repo.get!(Term, term.id)
    assert current.status == :active
    assert Academy.term_progress(current).phase == :final
    assert current.metadata["exam_attempt"]["id"] == final_attempt.attempt_id
    assert current.metadata["exam_attempt"]["status"] == "open"
  end

  test "a timed-out Basic Education midterm becomes the existing skipped-midterm path", %{
    realm: realm
  } do
    character = character_fixture(realm, "basic-exam-deadline", "Basic Exam Deadline")
    term = basic_term_ready_for_midterm(character)
    now = DateTime.add(DateTime.utc_now(), -(Academy.exam_duration_seconds() + 1), :second)

    assert {:ok, attempt} = Academy.start_exam_attempt(character.id, term.id, now: now)
    assert :ok = ExamDeadlineWorker.perform(attempt.deadline_worker)

    updated = Repo.get!(Term, term.id)
    assert updated.status == :active
    assert Academy.term_progress(updated).phase == :final
    assert Academy.term_progress(updated).midterm_skipped?
    assert updated.metadata["midterm_timeout_at"]
  end

  defp academy_core_term_ready_for_midterm(character) do
    {:ok, %{enrollment: basic}} = Academy.begin_basic_education(character, duration_game_days: 1)
    {:ok, _basic_complete} = Academy.complete_enrollment_by_id(basic.id, force: true)

    {:ok, %{enrollment: core}} =
      Academy.start_academy_track(character, :wizardry, %{
        primary_school: :fire,
        secondary_school: :air
      })

    {:ok, term} = Academy.begin_term(core.id)
    {:ok, _lecture_term} = Academy.open_lecture_phase(character.id, term.id)

    Enum.each(1..3, fn _lecture ->
      assert {:ok, _updated_term} = Academy.attend_lecture(character.id, term.id)
    end)

    {:ok, midterm_term} = Academy.close_club_window(character.id, term.id)
    midterm_term
  end

  defp basic_term_ready_for_midterm(character) do
    {:ok, %{enrollment: enrollment}} = Academy.begin_basic_education(character)
    {:ok, term} = Academy.begin_term(enrollment.id)
    {:ok, _lecture_term} = Academy.open_lecture_phase(character.id, term.id)

    Enum.each(1..3, fn _lecture ->
      assert {:ok, _updated_term} = Academy.attend_lecture(character.id, term.id)
    end)

    {:ok, midterm_term} = Academy.close_club_window(character.id, term.id)
    midterm_term
  end

  defp character_fixture(realm, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :new, level: 1, xp: 0})
    |> Repo.insert!()
  end
end
