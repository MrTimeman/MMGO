defmodule MMGO.ArenaTest do
  use MMGO.DataCase, async: false

  alias MMGO.Accounts
  alias MMGO.Accounts.{Account, Character, CharacterProfiles}
  alias MMGO.Arena
  alias MMGO.Arena.{Ladder, Titles}
  alias MMGO.Combat.Combat
  alias MMGO.Grimoires
  alias MMGO.Grimoires.{Grimoire, GrimoireEntry}
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "arena-test",
        name: "Arena Test Realm",
        is_default: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 0,
        y: 0,
        safe_zone: true
      })

    %{realm: realm, tower: tower}
  end

  test "profile requires three distinct allowlisted schools and permits opposed schools",
       context do
    account = account_fixture("school-picker")

    assert {:error, changeset} =
             Arena.create_profile(account, %{name: "Picker", schools: [:fire, :water]})

    assert %{schools: ["should have 3 item(s)"]} = errors_on(changeset)

    assert {:error, duplicate_changeset} =
             Arena.create_profile(account, %{
               name: "Picker",
               schools: [:fire, :fire, :air]
             })

    assert "must be distinct" in errors_on(duplicate_changeset).schools

    assert {:ok, profile} =
             Arena.create_profile(account, %{
               name: "Opposed Mage",
               schools: [:fire, :water, :death]
             })

    assert profile.schools == [:fire, :water, :death]
    assert profile.rating == 1_000
    assert profile.character.status == :active
    assert profile.character.level == 100
    assert profile.character.current_location_id == context.tower.id
    assert CharacterProfiles.arena?(profile.character)
    assert CharacterProfiles.hidden_presence?(profile.character)
  end

  test "arena and active world profiles coexist without entering world selection or presence", %{
    realm: realm,
    tower: tower
  } do
    account = account_fixture("dual-profile")
    world = world_character_fixture(account, realm, "World Mage", tower.id)

    assert {:ok, arena} =
             Arena.create_profile(account, %{
               name: "Arena Mage",
               schools: [:earth, :air, :life]
             })

    assert Accounts.get_character!(world.id).status == :active
    assert arena.character.status == :active
    assert Enum.map(Accounts.list_characters_for_account(account.id), & &1.id) == [world.id]

    assert Enum.map(Accounts.list_arena_characters_for_account(account.id), & &1.id) == [
             arena.character_id
           ]

    visible_ids =
      Enum.map(Accounts.list_active_characters_at_location(realm.id, tower.id), & &1.id)

    assert world.id in visible_ids
    refute arena.character_id in visible_ids

    assert {:ok, selected_world} = Accounts.switch_character(account.id, world.id)
    assert selected_world.status == :active
    assert Accounts.get_character!(arena.character_id).status == :active
  end

  test "profile receives three starter spells and unlimited free top-tier grimoire drafts",
       context do
    profile = arena_profile_fixture(context, "books", [:fire, :earth, :order])
    spells = Spells.list_spells_for_character(profile.character_id)
    grimoires = Grimoires.list_grimoires_for_character(profile.character_id)

    assert Enum.sort(Enum.map(spells, & &1.school)) == [:earth, :fire, :order]
    assert length(spells) == 3
    assert [%{status: :active, capacity: 15, weight: 0} = active] = grimoires
    assert active.metadata["arena"] == true
    assert length(active.entries) == 3

    assert {:ok, first_draft} = Arena.create_draft_grimoire(profile)
    assert {:ok, second_draft} = Arena.create_draft_grimoire(profile, %{name: "Counterbook"})
    assert first_draft.capacity == 15
    assert first_draft.weight == 0
    assert first_draft.metadata["free"] == true
    assert second_draft.name == "Counterbook"
    assert length(Grimoires.list_grimoires_for_character(profile.character_id)) == 3
  end

  test "custom 2v2 room cannot start until both full teams are ready", context do
    [host, ally, enemy_one, enemy_two] =
      Enum.map(
        [
          {"host", [:fire, :earth, :life]},
          {"ally", [:water, :air, :order]},
          {"enemy-one", [:death, :chaos, :fire]},
          {"enemy-two", [:earth, :life, :order]}
        ],
        fn {handle, schools} -> arena_profile_fixture(context, handle, schools) end
      )

    assert {:ok, room} =
             Arena.create_custom_room(host, %{
               team_size: 2,
               settings: %{turn_seconds: 90}
             })

    assert room.event_policy == :random
    assert room.event_codes != []
    assert room.settings["turn_seconds"] == 90
    assert {:ok, _room} = Arena.join_custom_room(room.code, ally, %{team: :a})
    assert {:ok, _room} = Arena.join_custom_room(room.code, enemy_one, %{team: :b})

    assert {:error, :teams_not_full} = Arena.start_custom_room(room, host)

    assert {:ok, _room} = Arena.join_custom_room(room.code, enemy_two, %{team: :b})
    assert {:error, :members_not_ready} = Arena.start_custom_room(room, host)

    Enum.each([host, ally, enemy_one, enemy_two], fn profile ->
      assert {:ok, _room} = Arena.toggle_ready(room, profile)
    end)

    assert {:ok, started} = Arena.start_custom_room(room, host)
    assert started.status == :active
    assert started.combat.kind == :arena_match
    assert length(started.combat.participants) == 4
    assert started.combat.environment_tags != []
    assert started.combat.metadata["arena_active_event_code"] in started.event_codes
    assert started.combat.metadata["arena_hp_per_member"] == 100
    assert started.combat.sides["a"]["shared_hp"] == 200
    assert started.combat.sides["b"]["shared_hp"] == 200
    assert started.combat.metadata["turn_seconds"] == 90

    turn = Repo.get_by!(MMGO.Combat.Turn, combat_id: started.combat.id, number: 1)
    assert MMGO.Combat.turn_lifecycle(turn)["deadline_seconds"] == 90
  end

  test "members can leave forming rooms and the host closes the room", context do
    host = arena_profile_fixture(context, "leaving-host", [:fire, :earth, :life])
    guest = arena_profile_fixture(context, "leaving-guest", [:water, :air, :order])

    assert {:ok, room} = Arena.create_custom_room(host, %{team_size: 1})
    assert {:ok, room} = Arena.join_custom_room(room.code, guest, %{team: :b})
    assert {:ok, room} = Arena.toggle_ready(room, host)
    assert {:ok, room} = Arena.toggle_ready(room, guest)
    assert Enum.all?(room.members, & &1.ready)

    assert {:ok, room} = Arena.leave_custom_room(room, guest)
    assert room.status == :forming
    assert Enum.map(room.members, & &1.profile_id) == [host.id]
    refute hd(room.members).ready
    assert Arena.active_match_for_profile(guest) == nil

    assert {:ok, closed} = Arena.leave_custom_room(room, host)
    assert closed.status == :cancelled
    assert Arena.active_match_for_profile(host) == nil
  end

  test "ranked queue keeps mismatched ratings apart", context do
    modest = arena_profile_fixture(context, "band-modest", [:fire, :water, :air])
    towering = arena_profile_fixture(context, "band-towering", [:earth, :life, :death])
    peer = arena_profile_fixture(context, "band-peer", [:chaos, :order, :fire])

    modest = set_standing!(modest, 1_000)
    towering = set_standing!(towering, 2_400)
    peer = set_standing!(peer, 1_060)

    assert {:ok, queued} = Arena.queue_ranked(modest)
    assert queued.status == :queued
    assert queued.metadata["rating_at_queue"] == 1_000
    assert queued.metadata["division_at_queue"] == "bronze"

    # An Archmage sits far outside the opening band, so this must open its own
    # queue entry rather than pair immediately.
    assert {:ok, second} = Arena.queue_ranked(towering)
    assert second.status == :queued
    assert second.id != queued.id

    # A peer inside the band pairs at once, and with the modest entry.
    assert {:ok, paired} = Arena.queue_ranked(peer)
    assert paired.status == :active
    assert paired.id == queued.id
  end

  defp set_standing!(profile, rating) do
    profile
    |> Ecto.Changeset.change(rating: rating, division: Ladder.division_for_rating(rating))
    |> Repo.update!()
  end

  test "ranked queue pairs 1v1 and settlement is idempotent", context do
    first = arena_profile_fixture(context, "ranked-one", [:fire, :water, :air])
    second = arena_profile_fixture(context, "ranked-two", [:earth, :life, :death])

    assert {:ok, queued} = Arena.queue_ranked(first)
    assert queued.status == :queued

    assert {:ok, paired} = Arena.queue_ranked(second)
    assert paired.status == :active
    assert paired.mode == :ranked
    assert length(paired.members) == 2

    combat =
      paired.combat
      |> Combat.changeset(%{
        status: :finished,
        winner_side: "a",
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

    assert {:ok, settled} = Arena.settle_match(combat)
    assert settled.status == :finished
    assert settled.winner_team == :a

    winner = Arena.get_profile!(first.id)
    loser = Arena.get_profile!(second.id)
    assert winner.rating > 1_000
    assert loser.rating < 1_000
    assert winner.wins == 1
    assert loser.losses == 1
    assert winner.matches_played == 1
    assert loser.matches_played == 1

    assert {:ok, same_settlement} = Arena.settle_match(combat)
    assert same_settlement.id == settled.id
    assert Arena.get_profile!(first.id).matches_played == 1
    assert Arena.get_profile!(second.id).matches_played == 1
  end

  # The release wipes every spell forged under the old rules; nobody may be left
  # with an empty book because of it.
  test "a wiped profile is re-issued a working book", context do
    profile = arena_profile_fixture(context, "wiped", [:fire, :water, :air])
    grimoire = Grimoires.active_grimoire_for_character(profile.character_id)

    Repo.delete_all(Spells.Spell)
    assert Repo.aggregate(GrimoireEntry, :count) == 0

    assert {:ok, _grimoire} = Arena.reissue_starter_spells(profile)

    entries =
      GrimoireEntry
      |> where([entry], entry.grimoire_id == ^grimoire.id)
      |> Repo.all()

    assert length(entries) == 3
    assert Enum.map(entries, & &1.slot_index) |> Enum.sort() == [1, 2, 3]

    # The same book the player already had, re-stocked rather than replaced.
    assert Grimoires.active_grimoire_for_character(profile.character_id).id == grimoire.id
  end

  # An arena loadout is a deck, not a sealed book. The active one has to stay
  # open or a player can never change what they take into a fight.
  test "the active arena loadout accepts and releases spells", context do
    profile = arena_profile_fixture(context, "loadout", [:fire, :water, :air])
    grimoire = Grimoires.active_grimoire_for_character(profile.character_id)

    assert grimoire.status == :active
    assert Grimoires.writable?(grimoire)
    assert Grimoires.arena?(grimoire)

    forged =
      Spells.create_spell(
        Repo.get!(Character, profile.character_id),
        %{
          name: "Новая формула",
          formula: "Ignis Novus",
          school: :fire,
          description: "Свежая формула для проверки раскладки.",
          targeting: :enemy,
          delivery_form: :sphere,
          effects: [
            %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
          ],
          failure_profile: %{difficulty: 4, base_success_rate: 90, partial_success_rate: 5}
        }
      )
      |> elem(1)

    before =
      Repo.aggregate(from(e in GrimoireEntry, where: e.grimoire_id == ^grimoire.id), :count)

    assert {:ok, _entry} = Grimoires.inscribe_spell(grimoire, forged)

    assert Repo.aggregate(from(e in GrimoireEntry, where: e.grimoire_id == ^grimoire.id), :count) ==
             before + 1

    # And a formula can be swapped back out, which the loadout needs just as much.
    assert {:ok, _removed} =
             Grimoires.erase_spell(Grimoires.get_grimoire!(grimoire.id), forged)

    assert Repo.aggregate(from(e in GrimoireEntry, where: e.grimoire_id == ^grimoire.id), :count) ==
             before
  end

  # The seed runs this on every deploy, so it must fill only what the wipe
  # emptied and do nothing on the deploy after that.
  test "restocking fills emptied books once and is safe to repeat", context do
    wiped = arena_profile_fixture(context, "restock-wiped", [:fire, :water, :air])
    stocked = arena_profile_fixture(context, "restock-stocked", [:earth, :life, :death])

    stocked_entries_before =
      GrimoireEntry
      |> join(:inner, [entry], grimoire in Grimoire, on: grimoire.id == entry.grimoire_id)
      |> where([_entry, grimoire], grimoire.owner_character_id == ^stocked.character_id)
      |> Repo.aggregate(:count)

    # Empty only the first player's book, as the release migration would.
    Repo.delete_all(
      from spell in Spells.Spell,
        where: spell.creator_character_id == ^wiped.character_id
    )

    assert [restocked_id] = Arena.restock_empty_arena_books()
    assert restocked_id == wiped.id

    # Repeating it changes nothing.
    assert Arena.restock_empty_arena_books() == []

    assert Repo.aggregate(
             from(entry in GrimoireEntry,
               join: grimoire in Grimoire,
               on: grimoire.id == entry.grimoire_id,
               where: grimoire.owner_character_id == ^stocked.character_id
             ),
             :count
           ) == stocked_entries_before
  end

  test "a title bout settles the seat and leaves the ladder alone", context do
    champion = arena_profile_fixture(context, "bout-champion", [:fire, :water, :air])
    deputy = arena_profile_fixture(context, "bout-deputy", [:earth, :life, :death])
    challenger = arena_profile_fixture(context, "bout-challenger", [:chaos, :order, :fire])

    [champion, deputy, challenger] =
      Enum.map([champion, deputy, challenger], &set_standing!(&1, 2_600))

    {:ok, _seat} = Titles.crown_champion(champion)
    {:ok, offer} = Titles.appoint_deputy(champion, deputy)
    {:ok, _held} = Titles.accept_deputy(offer)

    {:ok, challenge} = Titles.challenge_deputy(challenger)

    assert {:ok, bout} = Arena.start_title_bout(challenge)
    assert bout.status == :active
    assert bout.mode == :custom
    assert bout.metadata["title_challenge_id"] == challenge.id

    # A title bout is fought under ordinary arena rules; only the seat is at stake.
    assert bout.settings["rules"]["rank"] == "own"
    assert bout.settings["rules"]["mana"] == "standard"

    combat =
      bout.combat
      |> Combat.changeset(%{
        status: :finished,
        winner_side: "a",
        finished_at: DateTime.utc_now()
      })
      |> Repo.update!()

    assert {:ok, settled} = Arena.settle_match(combat)
    assert settled.winner_team == :a

    # The challenger earned the right to the Champion, and nobody's rating moved.
    assert Titles.gauntlet_right?(challenger)
    assert Arena.get_profile!(challenger.id).rating == 2_600
    assert Arena.get_profile!(deputy.id).rating == 2_600
  end

  test "the Champion's rank comes from the seat, never from rating", context do
    profile = arena_profile_fixture(context, "seat-rank", [:fire, :earth, :order])

    # Rating far past the old Champion floor still settles at Archmage.
    profile =
      profile
      |> Arena.Profile.changeset(%{rating: 9_000, division: :archmage})
      |> Repo.update!()

    assert Arena.rank(profile) == :archmage
    assert Arena.casting_rank(profile) == :archmage

    {:ok, _seat} = Titles.crown_champion(profile)

    # The ladder still reads Archmage; the seat is what opens the band.
    profile = Arena.get_profile!(profile.id)
    assert Arena.rank(profile) == :archmage
    assert Arena.casting_rank(profile) == :champion
  end

  test "the empty throne is filled from the top of the ladder", context do
    lesser = arena_profile_fixture(context, "throne-lesser", [:fire, :water, :air])
    greater = arena_profile_fixture(context, "throne-greater", [:earth, :life, :death])

    # Nobody stands high enough yet, so the seat stays empty.
    assert Titles.ensure_champion_seated() == :noop
    assert Titles.holder(:champion) == nil

    for {profile, rating} <- [{lesser, 2_200}, {greater, 2_600}] do
      profile
      |> Arena.Profile.changeset(%{rating: rating, division: :archmage})
      |> Repo.update!()
    end

    assert {:ok, _seat} = Titles.ensure_champion_seated()
    assert Titles.holder(:champion).profile_id == greater.id

    # A seated throne is left alone.
    assert Titles.ensure_champion_seated() == :noop
  end

  test "taking a seat widens the book the shelf actually enforces", context do
    champion = arena_profile_fixture(context, "seat-champ", [:fire, :earth, :order])
    deputy = arena_profile_fixture(context, "seat-deputy", [:water, :air, :life])

    assert [%{capacity: 15}] = Grimoires.list_grimoires_for_character(champion.character_id)

    {:ok, _seat} = Titles.crown_champion(champion)

    assert [%{capacity: 45}] = Grimoires.list_grimoires_for_character(champion.character_id)

    {:ok, offer} = Titles.appoint_deputy(champion, deputy)

    # The offer alone changes nothing: the book widens when the seat is taken.
    assert [%{capacity: 15}] = Grimoires.list_grimoires_for_character(deputy.character_id)

    {:ok, _held} = Titles.accept_deputy(offer)

    assert [%{capacity: 45}] = Grimoires.list_grimoires_for_character(deputy.character_id)
  end

  # The Arena is unplayable alone. Training needs no opponent, no queue, and
  # costs nothing: it exists so a player can see what their formulas do.
  test "the training hall opens a fight with nobody else in it", context do
    profile = arena_profile_fixture(context, "trainee", [:fire, :earth, :order])
    rating_before = profile.rating

    assert {:ok, match} = Arena.start_training(profile)
    assert match.status == :active
    assert is_binary(match.combat_id)

    combat = MMGO.Combat.get_combat!(match.combat_id)
    assert length(combat.participants) == 2

    # One of them is the player; the other is nobody's character.
    assert Enum.any?(combat.participants, &(&1.character_id == profile.character_id))
    assert Enum.any?(combat.participants, &(&1.character_id == nil and &1.actor_template_id))

    # Nothing about it is ranked.
    assert match.mode == :custom
    assert combat.metadata["training"] == true
    assert Arena.get_profile!(profile.id).rating == rating_before
  end

  test "training reuses one dummy per realm rather than breeding them", context do
    first = arena_profile_fixture(context, "trainee-one", [:fire, :earth, :order])
    second = arena_profile_fixture(context, "trainee-two", [:water, :air, :life])

    assert {:ok, _one} = Arena.start_training(first)
    assert {:ok, _two} = Arena.start_training(second)

    assert length(MMGO.Actors.list_actor_templates(context.realm.id)) == 1
  end

  defp arena_profile_fixture(context, handle, schools) do
    account = account_fixture("arena-#{handle}")

    {:ok, profile} =
      Arena.create_profile(account, %{
        name: "Mage #{handle}",
        schools: schools
      })

    assert profile.character.realm_id == context.realm.id
    profile
  end

  defp account_fixture(handle) do
    %Account{}
    |> Account.registration_changeset(%{
      display_name: "Mage #{handle}",
      handle: handle
    })
    |> Repo.insert!()
  end

  defp world_character_fixture(account, realm, name, location_id) do
    %Character{
      account_id: account.id,
      realm_id: realm.id,
      current_location_id: location_id
    }
    |> Character.changeset(%{name: name, status: :active})
    |> Repo.insert!()
  end
end
