defmodule MMGO.Academy do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Academy.{CompleteEnrollmentWorker, Enrollment, Specialization}
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.Travel.Clock

  @tracks [:wizardry, :alchemy, :mastery]
  @schools [:fire, :water, :earth, :air, :life, :death, :chaos, :order]

  def current_enrollment(character_id) when is_binary(character_id) do
    Repo.get_by(Enrollment, character_id: character_id, status: :active)
  end

  def enrollment_history(character_id) when is_binary(character_id) do
    Repo.all(
      from enrollment in Enrollment,
        where: enrollment.character_id == ^character_id,
        order_by: [asc: enrollment.inserted_at]
    )
  end

  def active_specialization(character_id) when is_binary(character_id) do
    Repo.get_by(Specialization, character_id: character_id, status: :active)
  end

  def list_specializations(character_id) when is_binary(character_id) do
    Repo.all(
      from specialization in Specialization,
        where: specialization.character_id == ^character_id,
        order_by: [asc: specialization.inserted_at]
    )
  end

  def school_permitted?(character_id, school) when is_binary(character_id) do
    case active_specialization(character_id) do
      %Specialization{track: :wizardry} = specialization ->
        Atom.to_string(specialization.primary_school) == school or
          Atom.to_string(specialization.secondary_school) == school

      %Specialization{} ->
        false

      nil ->
        false
    end
  end

  def basic_education_completed?(character_id) when is_binary(character_id) do
    completed_program?(character_id, :basic_education)
  end

  def academic_affiliated?(character_id) when is_binary(character_id) do
    not is_nil(current_enrollment(character_id)) or
      not is_nil(active_specialization(character_id)) or
      basic_education_completed?(character_id)
  end

  def begin_basic_education(%Character{} = character, opts \\ []) do
    start_program(character, :basic_education, nil, %{}, opts)
  end

  def start_academy_track(%Character{} = character, track, attrs \\ %{}, opts \\ []) do
    start_program(character, :academy_core, track, attrs, opts)
  end

  def start_extended_study(%Character{} = character, opts \\ []) do
    start_program(character, :extended_study, nil, %{}, opts)
  end

  def start_academia(%Character{} = character, opts \\ []) do
    start_program(character, :academia, nil, %{}, opts)
  end

  def complete_enrollment_by_id(enrollment_id, opts \\ []) when is_binary(enrollment_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force, false)

    Repo.transaction(fn ->
      enrollment = lock_enrollment!(enrollment_id)
      character = lock_character!(enrollment.character_id)

      cond do
        enrollment.status != :active ->
          Repo.rollback(enrollment_changeset("enrollment is not active"))

        not force? and DateTime.compare(now, enrollment.expected_completion_at) == :lt ->
          Repo.rollback(enrollment_changeset("enrollment is not due yet"))

        true ->
          updated_enrollment =
            enrollment
            |> Enrollment.changeset(%{status: :completed, completed_at: now})
            |> Repo.update!()

          updated_character =
            character
            |> Character.changeset(%{
              status:
                if(enrollment.program_type == :basic_education,
                  do: :active,
                  else: character.status
                )
            })
            |> Repo.update!()

          {:ok, %{character: updated_character}} =
            Progression.grant_xp(Repo, updated_character, completion_xp(enrollment), %{
              "source" => "academy_enrollment_completion",
              "enrollment_id" => enrollment.id,
              "program_type" => to_string(enrollment.program_type),
              "granted_at" => now
            })

          specialization = maybe_upsert_specialization!(updated_enrollment, now)

          %{
            enrollment: updated_enrollment,
            character: updated_character,
            specialization: specialization
          }
      end
    end)
    |> normalize_transaction_result()
  end

  def complete_due_enrollments(now \\ DateTime.utc_now()) do
    Enrollment
    |> where(
      [enrollment],
      enrollment.status == :active and enrollment.expected_completion_at <= ^now
    )
    |> Repo.all()
    |> Enum.map(fn enrollment ->
      complete_enrollment_by_id(enrollment.id, now: now, force: true)
    end)
  end

  defp start_program(%Character{} = character, program_type, track, attrs, opts) do
    now = Keyword.get(opts, :started_at, DateTime.utc_now())
    duration_game_days = Keyword.get(opts, :duration_game_days, default_duration(program_type))

    funding_type =
      Map.get(attrs, :funding_type) || Map.get(attrs, "funding_type") ||
        default_funding(program_type)

    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      character = lock_character!(character.id)

      validate_program_start!(character, program_type, track, attrs)

      expected_completion_at = Clock.arrival_at(now, duration_game_days)

      enrollment =
        %Enrollment{}
        |> Enrollment.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          program_type: program_type,
          track: track,
          funding_type: funding_type,
          started_at: now,
          expected_completion_at: expected_completion_at,
          metadata: enrollment_metadata(program_type, track, attrs, duration_game_days)
        })
        |> Repo.insert!()

      job =
        %{"enrollment_id" => enrollment.id}
        |> CompleteEnrollmentWorker.new(
          schedule_in: max(DateTime.diff(expected_completion_at, DateTime.utc_now(), :second), 0)
        )
        |> Oban.insert!()

      %{enrollment: enrollment, job: job}
    end)
    |> normalize_transaction_result()
  end

  defp validate_program_start!(%Character{} = character, :basic_education, _track, _attrs) do
    cond do
      current_enrollment(character.id) ->
        Repo.rollback(enrollment_changeset("character already has an active enrollment"))

      completed_program?(character.id, :basic_education) ->
        Repo.rollback(enrollment_changeset("basic education has already been completed"))

      true ->
        :ok
    end
  end

  defp validate_program_start!(%Character{} = character, :academy_core, track, attrs) do
    cond do
      current_enrollment(character.id) ->
        Repo.rollback(enrollment_changeset("character already has an active enrollment"))

      not completed_program?(character.id, :basic_education) ->
        Repo.rollback(enrollment_changeset("basic education must be completed first"))

      active_specialization(character.id) ->
        Repo.rollback(enrollment_changeset("character already has an active specialization"))

      track not in @tracks ->
        Repo.rollback(enrollment_changeset("academy track is invalid"))

      true ->
        validate_track_attrs!(track, attrs)
    end
  end

  defp validate_program_start!(%Character{} = character, :extended_study, _track, _attrs) do
    cond do
      current_enrollment(character.id) ->
        Repo.rollback(enrollment_changeset("character already has an active enrollment"))

      not completed_program?(character.id, :academy_core) ->
        Repo.rollback(enrollment_changeset("academy core study must be completed first"))

      true ->
        :ok
    end
  end

  defp validate_program_start!(%Character{} = character, :academia, _track, _attrs) do
    cond do
      current_enrollment(character.id) ->
        Repo.rollback(enrollment_changeset("character already has an active enrollment"))

      not completed_program?(character.id, :academy_core) ->
        Repo.rollback(enrollment_changeset("academy core study must be completed first"))

      true ->
        :ok
    end
  end

  defp validate_track_attrs!(:wizardry, attrs) do
    primary_school = normalize_school(Map.get(attrs, "primary_school"))
    secondary_school = normalize_school(Map.get(attrs, "secondary_school"))

    cond do
      is_nil(primary_school) or is_nil(secondary_school) ->
        Repo.rollback(enrollment_changeset("wizardry requires two valid schools"))

      primary_school == secondary_school ->
        Repo.rollback(enrollment_changeset("wizardry schools must be distinct"))

      true ->
        :ok
    end
  end

  defp validate_track_attrs!(_track, _attrs), do: :ok

  defp maybe_upsert_specialization!(
         %Enrollment{program_type: :academy_core, track: track} = enrollment,
         now
       )
       when track in @tracks do
    attrs = %{
      character_id: enrollment.character_id,
      realm_id: enrollment.realm_id,
      track: track,
      status: :active,
      started_at: now,
      primary_school: normalize_school(enrollment.metadata["primary_school"]),
      secondary_school: normalize_school(enrollment.metadata["secondary_school"]),
      metadata: %{"source_enrollment_id" => enrollment.id}
    }

    %Specialization{}
    |> Specialization.changeset(attrs)
    |> Repo.insert!()
  end

  defp maybe_upsert_specialization!(_enrollment, _now), do: nil

  defp completed_program?(character_id, program_type) do
    Repo.exists?(
      from enrollment in Enrollment,
        where:
          enrollment.character_id == ^character_id and enrollment.program_type == ^program_type and
            enrollment.status == :completed
    )
  end

  defp completion_xp(%Enrollment{program_type: :basic_education}), do: 100
  defp completion_xp(%Enrollment{program_type: :academy_core}), do: 250
  defp completion_xp(%Enrollment{program_type: :extended_study}), do: 180
  defp completion_xp(%Enrollment{program_type: :academia}), do: 320

  defp default_duration(:basic_education), do: 3640
  defp default_duration(:academy_core), do: 1092
  defp default_duration(:extended_study), do: 728
  defp default_duration(:academia), do: 1456

  defp default_funding(:basic_education), do: :none
  defp default_funding(_program_type), do: :self_funded

  defp enrollment_metadata(program_type, track, attrs, duration_game_days) do
    attrs
    |> Map.take(["primary_school", "secondary_school", "notes"])
    |> Map.put("program_type", Atom.to_string(program_type))
    |> then(fn metadata ->
      if(track, do: Map.put(metadata, "track", Atom.to_string(track)), else: metadata)
    end)
    |> Map.put("duration_game_days", duration_game_days)
  end

  defp normalize_school(school) when school in @schools, do: school

  defp normalize_school(school) when is_binary(school) do
    case school do
      "fire" -> :fire
      "water" -> :water
      "earth" -> :earth
      "air" -> :air
      "life" -> :life
      "death" -> :death
      "chaos" -> :chaos
      "order" -> :order
      _other -> nil
    end
  end

  defp normalize_school(_school), do: nil

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_enrollment!(enrollment_id) do
    Enrollment
    |> where([enrollment], enrollment.id == ^enrollment_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp enrollment_changeset(message) do
    %Enrollment{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
