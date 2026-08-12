defmodule MMGO.Spells.CreationTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Spells.{Creation, CreationAttempt, Spell}
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "ritual-realm",
        name: "Ritual Realm",
        is_default: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "ritual-tower",
        name: "Ritual Tower",
        kind: :tower,
        x: 10,
        y: 20,
        safe_zone: false
      })

    character = character_fixture(realm, tower, "ritual-caster", "Ritual Caster")
    %{realm: realm, tower: tower, character: character}
  end

  test "begin persists even an incomplete circle for one shared-world hour", %{
    character: character,
    tower: tower
  } do
    now = ~U[2026-08-03 15:00:00.000000Z]

    assert {:ok, %{attempt: attempt, resolve_job: resolve_job, reveal_job: reveal_job}} =
             Creation.begin(
               character,
               tower.id,
               %{"school" => "fire", "actio" => "", "tempus" => ""},
               now: now
             )

    assert attempt.status == :queued
    assert attempt.started_at == now
    assert DateTime.diff(attempt.completes_at, now, :second) == 10

    assert attempt.input == %{
             "circle" => %{"school" => "fire", "actio" => "", "tempus" => ""}
           }

    assert resolve_job.args == %{"attempt_id" => attempt.id}
    assert reveal_job.args == %{"attempt_id" => attempt.id}
    assert Creation.active_attempt(character.id).id == attempt.id

    assert {:error, :spell_creation_in_progress} =
             Creation.begin(character, tower.id, %{"school" => "air"}, now: now)

    assert Repo.aggregate(CreationAttempt, :count, :id) == 1
  end

  test "the server-only immediate policy keeps a durable attempt but removes the reveal wait", %{
    character: character,
    tower: tower
  } do
    now = ~U[2026-08-03 15:00:00.000000Z]

    assert {:ok, %{attempt: attempt, resolve_job: resolve_job, reveal_job: reveal_job}} =
             Creation.begin(character, tower.id, %{"school" => "life", "actio" => "Vocatio"},
               now: now,
               immediate?: true
             )

    assert attempt.status == :queued
    assert attempt.started_at == now
    assert attempt.completes_at == now
    assert resolve_job.args == %{"attempt_id" => attempt.id}
    assert reveal_job.args == %{"attempt_id" => attempt.id}

    assert {:ok, %{action: :resolve}} = Creation.claim_resolution(attempt.id)

    assert {:ok, revealed} =
             Creation.finalize_failure(attempt.id, :invalid_spell_circle, now: now)

    assert revealed.status == :revealed
    assert revealed.revealed_at == now
    assert Creation.active_attempt(character.id) == nil
  end

  test "invalid transport data is recorded as a failed payload rather than trusted", %{
    realm: realm,
    tower: tower
  } do
    character = character_fixture(realm, tower, "invalid-ritual", "Invalid Ritual")

    assert {:ok, %{attempt: attempt}} =
             Creation.begin(character, tower.id, %{"actio" => <<255>>})

    assert attempt.input == %{"invalid_payload" => true}
  end

  test "an attempt spell remains hidden until its global deadline and retries are idempotent", %{
    character: character,
    tower: tower
  } do
    now = ~U[2026-08-03 15:00:00.000000Z]
    assert {:ok, %{attempt: attempt}} = Creation.begin(character, tower.id, %{}, now: now)
    assert {:ok, %{action: :resolve}} = Creation.claim_resolution(attempt.id)

    attrs = spell_attrs("Ritual Spark")

    assert {:ok, spell} =
             Spells.create_spell(character, attrs, creation_attempt_id: attempt.id)

    assert {:ok, same_spell} =
             Spells.create_spell(character, attrs, creation_attempt_id: attempt.id)

    assert same_spell.id == spell.id
    assert Spells.list_spells_for_character(character.id) == []
    assert Spells.get_owned_spell(character, spell.id) == nil

    assert {:ok, sealed_attempt} =
             Creation.finalize_success(attempt.id, now: DateTime.add(now, 1, :second))

    assert sealed_attempt.status == :sealed_success
    assert sealed_attempt.outcome == %{"kind" => "success", "spell_id" => spell.id}
    assert Spells.list_spells_for_character(character.id) == []

    assert {:ok, revealed_attempt} =
             Creation.reveal(attempt.id, now: attempt.completes_at)

    assert revealed_attempt.status == :revealed
    assert [%Spell{id: spell_id}] = Spells.list_spells_for_character(character.id)
    assert spell_id == spell.id
    assert %Spell{id: ^spell_id} = Spells.get_owned_spell(character, spell.id)
    assert Creation.active_attempt(character.id) == nil
  end

  test "a failed ritual removes any hidden spell and reveals only a bounded failure", %{
    character: character,
    tower: tower
  } do
    now = ~U[2026-08-03 15:00:00.000000Z]
    assert {:ok, %{attempt: attempt}} = Creation.begin(character, tower.id, %{}, now: now)
    assert {:ok, %{action: :resolve}} = Creation.claim_resolution(attempt.id)

    assert {:ok, spell} =
             Spells.create_spell(character, spell_attrs("Discarded Spark"),
               creation_attempt_id: attempt.id
             )

    assert {:ok, sealed_attempt} =
             Creation.finalize_failure(attempt.id, :invalid_spell_circle,
               now: DateTime.add(now, 1, :second)
             )

    assert sealed_attempt.status == :sealed_failure

    assert sealed_attempt.outcome == %{
             "kind" => "failure",
             "failure_kind" => "user_error",
             "code" => "invalid_spell_circle"
           }

    assert Repo.get(Spell, spell.id) == nil
    assert Spells.list_spells_for_character(character.id) == []

    assert {:ok, %{status: :revealed}} =
             Creation.reveal(attempt.id, now: attempt.completes_at)

    assert Spells.list_spells_for_character(character.id) == []
  end

  test "nested spell validation paths survive ritual failure diagnostics", %{
    character: character,
    tower: tower
  } do
    now = ~U[2026-08-03 15:00:00.000000Z]
    assert {:ok, %{attempt: attempt}} = Creation.begin(character, tower.id, %{}, now: now)
    assert {:ok, %{action: :resolve}} = Creation.claim_resolution(attempt.id)

    invalid_changeset =
      %Spell{creator_character_id: character.id, realm_id: character.realm_id}
      |> Spell.changeset(
        spell_attrs("Broken Spark")
        |> put_in([:effects, Access.at(0), :state], "invented_state")
      )

    refute invalid_changeset.valid?

    assert {:ok, failed_attempt} =
             Creation.finalize_failure(attempt.id, invalid_changeset,
               now: DateTime.add(now, 1, :second)
             )

    assert "effects.0.state" in failed_attempt.outcome["fields"]
  end

  test "an already revealed attempt rebroadcasts on retry", %{
    character: character,
    tower: tower
  } do
    Phoenix.PubSub.subscribe(MMGO.PubSub, Creation.character_topic(character.id))
    now = ~U[2026-08-03 15:00:00.000000Z]

    assert {:ok, %{attempt: attempt}} = Creation.begin(character, tower.id, %{}, now: now)
    assert {:ok, %{action: :resolve}} = Creation.claim_resolution(attempt.id)

    assert {:ok, _sealed_attempt} =
             Creation.finalize_failure(attempt.id, :invalid_spell_circle,
               now: DateTime.add(now, 1, :second)
             )

    assert {:ok, %{status: :revealed}} =
             Creation.reveal(attempt.id, now: attempt.completes_at)

    assert_receive {:spell_creation_revealed, attempt_id}
    assert attempt_id == attempt.id

    assert {:ok, %{status: :revealed}} =
             Creation.reveal(attempt.id, now: attempt.completes_at)

    assert_receive {:spell_creation_revealed, retried_attempt_id}
    assert retried_attempt_id == attempt.id
  end

  test "leaving the ritual location before the world hour ends destroys a sealed success", %{
    realm: realm,
    character: character,
    tower: tower
  } do
    {:ok, courtyard} =
      Worlds.create_location(realm, %{
        slug: "ritual-courtyard",
        name: "Ritual Courtyard",
        kind: :city,
        x: 30,
        y: 40,
        safe_zone: true
      })

    now = ~U[2026-08-03 15:00:00.000000Z]
    assert {:ok, %{attempt: attempt}} = Creation.begin(character, tower.id, %{}, now: now)
    assert {:ok, %{action: :resolve}} = Creation.claim_resolution(attempt.id)

    assert {:ok, hidden_spell} =
             Spells.create_spell(character, spell_attrs("Displaced Spark"),
               creation_attempt_id: attempt.id
             )

    assert {:ok, %{status: :sealed_success}} =
             Creation.finalize_success(attempt.id, now: DateTime.add(now, 1, :second))

    character
    |> Character.travel_changeset(%{current_location_id: courtyard.id})
    |> Repo.update!()

    assert {:ok, revealed_attempt} =
             Creation.reveal(attempt.id, now: attempt.completes_at)

    assert revealed_attempt.status == :revealed
    assert revealed_attempt.outcome["kind"] == "failure"
    assert revealed_attempt.outcome["code"] == "spellbook_location"
    assert Repo.get(Spell, hidden_spell.id) == nil
  end

  test "a late success finalization checks displacement inside its reveal transaction", %{
    realm: realm,
    character: character,
    tower: tower
  } do
    {:ok, archive} =
      Worlds.create_location(realm, %{
        slug: "late-ritual-archive",
        name: "Late Ritual Archive",
        kind: :city,
        x: 50,
        y: 60,
        safe_zone: true
      })

    now = ~U[2026-08-03 15:00:00.000000Z]
    assert {:ok, %{attempt: attempt}} = Creation.begin(character, tower.id, %{}, now: now)
    assert {:ok, %{action: :resolve}} = Creation.claim_resolution(attempt.id)

    assert {:ok, hidden_spell} =
             Spells.create_spell(character, spell_attrs("Late Displaced Spark"),
               creation_attempt_id: attempt.id
             )

    character
    |> Character.travel_changeset(%{current_location_id: archive.id})
    |> Repo.update!()

    assert {:ok, revealed_attempt} =
             Creation.finalize_success(attempt.id, now: attempt.completes_at)

    assert revealed_attempt.status == :revealed
    assert revealed_attempt.outcome["kind"] == "failure"
    assert revealed_attempt.outcome["code"] == "spellbook_location"
    assert Repo.get(Spell, hidden_spell.id) == nil
  end

  defp spell_attrs(name) do
    %{
      name: name,
      formula: "Ignis Momentum",
      incantation_slots: %{"actio" => "Ignis", "tempus" => "Momentum"},
      school: :fire,
      description: "A spell sealed behind a world-clock ritual.",
      targeting: :enemy,
      delivery_form: :sphere,
      effects: [
        %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
      ],
      failure_profile: %{difficulty: 5, base_success_rate: 90, partial_success_rate: 5}
    }
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
