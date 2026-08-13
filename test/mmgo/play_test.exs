defmodule MMGO.PlayTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.AI.Request
  alias MMGO.Bases
  alias MMGO.Arena
  alias MMGO.Dungeons
  alias MMGO.Economy
  alias MMGO.Economy.EconomyAccount
  alias MMGO.Events
  alias MMGO.Grimoires
  alias MMGO.Inventory
  alias MMGO.Inventory.InventoryItem
  alias MMGO.Organizations
  alias MMGO.Parties
  alias MMGO.Play
  alias MMGO.PVP
  alias MMGO.Repo
  alias MMGO.Scavenging
  alias MMGO.Spells
  alias MMGO.Spells.{Creation, Spell}
  alias MMGO.Travel
  alias MMGO.Travel.Journey
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 100_000)

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 100,
        y: 100,
        safe_zone: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 800,
        y: 220,
        safe_zone: false
      })

    {:ok, _route} =
      Worlds.create_route(realm, %{
        name: "Capital Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 10,
        risk_level: 20,
        bidirectional: true
      })

    {:ok, ration_template} =
      Inventory.create_item_template(%{
        code: "travel_ration",
        name: "Travel Ration",
        item_type: :food,
        stackable: true,
        weight: 1,
        max_durability: 0,
        nutrition_units: 1,
        actions: []
      })

    character = character_fixture(realm, city, "facade-mage", "Facade Mage")
    opponent = character_fixture(realm, city, "facade-rival", "Facade Rival")
    {:ok, _rations} = Inventory.grant_item(character, ration_template, %{quantity: 20})

    %{realm: realm, city: city, tower: tower, character: character, opponent: opponent}
  end

  test "load_demo_state/1 composes the current UI state", %{
    city: city,
    character: character
  } do
    assert {:ok, state} = Play.load_demo_state(character.id)

    assert state.character.id == character.id
    assert state.current_location.id == city.id
    assert state.food_units == 20
    assert [%{destination_location: %{slug: "the-tower"}}] = state.routes
    assert state.active_journey == nil
    assert state.spells == []
    assert state.duel.active_duel == nil
    assert state.duel.pending_duels == []
  end

  test "start_journey/2 starts travel by destination slug and refreshes state", %{
    character: character,
    tower: tower
  } do
    assert {:ok, %{journey: journey, character: updated_character}} =
             Play.start_journey(character.id, "the-tower")

    assert journey.to_location_id == tower.id
    assert journey.to_location.slug == "the-tower"
    assert updated_character.id == character.id
    assert Travel.active_journey(character.id).id == journey.id

    assert {:ok, state} = Play.load_demo_state(character.id)
    assert state.active_journey.id == journey.id
    assert state.routes == []
  end

  test "travel_state/1 composes the journey and survival values for the web", %{
    character: character,
    tower: tower
  } do
    assert {:ok, %{journey: journey}} = Play.start_journey(character.id, "the-tower")

    assert {:ok, state} = Play.travel_state(character.id)

    assert state.character.id == character.id
    assert state.current_location.slug == "capital-city"
    assert state.journey.id == journey.id
    assert state.journey.to_location.id == tower.id
    assert state.food_units < 20
    assert state.carried_weight > 0
    assert state.carry_capacity > state.carried_weight
    assert state.atmosphere.ambient_cue == "city"
    assert state.atmosphere.major_event_cue == "journey"
  end

  test "world_hub_state/1 stays inside the character's realm and lists nearby stationary actors",
       %{
         realm: realm,
         city: city,
         character: character
       } do
    nearby = character_fixture(realm, city, "nearby", "Nearby")
    npc = character_fixture(realm, city, "academy-professor", "Academy Professor")

    Account
    |> Repo.get!(npc.account_id)
    |> Ecto.Changeset.change(settings: %{"npc" => true})
    |> Repo.update!()

    {:ok, other_realm} =
      Worlds.create_realm(%{slug: "other-realm", name: "Other Realm", is_default: false})

    {:ok, other_city} =
      Worlds.create_location(other_realm, %{
        slug: "other-city",
        name: "Other City",
        kind: :city,
        x: 50,
        y: 50,
        safe_zone: true
      })

    _other = character_fixture(other_realm, other_city, "other", "Other")

    assert {:ok, state} = Play.world_hub_state(character)
    assert state.realm.id == realm.id
    assert state.current_location.id == city.id
    assert state.world_time.month_number in 1..13
    nearby_ids = MapSet.new(Enum.map(state.nearby_characters, & &1.id))
    assert nearby.id in nearby_ids
    refute npc.id in nearby_ids
    assert length(state.nearby_characters) == 2
    assert state.atmosphere.ambient_cue == "city"
    assert state.atmosphere.major_event_cue == nil
  end

  test "world_hub_state/1 exposes only aggregate organization economic activity for map overlays",
       %{
         city: city,
         character: character
       } do
    assert {:ok, %{organization: organization}} =
             Organizations.create_organization(character, :company, "Map Company", %{
               linked_location_ids: [city.id]
             })

    assert {:ok, _grant} =
             Economy.grant_from_treasury(city.realm_id |> Worlds.get_realm!(), character, 25)

    assert {:ok, _deposit} = Organizations.deposit_to_treasury(organization, character, 25)

    assert {:ok, state} = Play.world_hub_state(character)
    assert state.organization_economic_activity == %{organization.id => 1}
  end

  test "activity options are scoped to the current character's active arrival event", %{
    character: character,
    opponent: opponent
  } do
    own_event = Events.current_event(character)
    foreign_event = Events.current_event(opponent)

    assert {:error, :event_not_found} =
             Play.resolve_activity_option(character, foreign_event.id, "academy")

    assert Events.get_instance(foreign_event.id).status == :active

    assert {:ok, %{action: %{type: :navigate, to: "/academy/bulletin-board"}}} =
             Play.resolve_activity_option(character, own_event.id, "academy")
  end

  test "overworld facade only accepts nearby participants and an owned open encounter", %{
    realm: realm,
    city: city,
    character: character,
    opponent: opponent
  } do
    observer = character_fixture(realm, city, "observer", "Observer")

    {:ok, remote_realm} =
      Worlds.create_realm(%{slug: "remote-realm", name: "Remote Realm", is_default: false})

    {:ok, remote_city} =
      Worlds.create_location(remote_realm, %{
        slug: "remote-city",
        name: "Remote City",
        kind: :city,
        x: 300,
        y: 300,
        safe_zone: false
      })

    remote = character_fixture(remote_realm, remote_city, "remote", "Remote")

    assert {:error, :target_not_found} = Play.start_overworld_encounter(character, remote.id)

    assert {:ok, %{encounter: encounter}} =
             Play.start_overworld_encounter(character, opponent.id)

    assert encounter.counterpart.id == opponent.id
    assert encounter.can_respond?

    assert {:error, :encounter_not_found} =
             Play.respond_to_overworld_encounter(observer, encounter.id, "greet")

    assert {:ok, %{encounter: updated}} =
             Play.respond_to_overworld_encounter(character, encounter.id, "greet")

    refute updated.can_respond?
  end

  test "traveler contact facade exposes role-specific consent and remains scoped", %{
    realm: realm,
    city: city,
    character: character,
    opponent: opponent
  } do
    observer = character_fixture(realm, city, "contact-observer", "Contact Observer")

    assert {:ok, %{encounter: outgoing}} =
             Play.request_traveler_contact(character, opponent.id)

    assert outgoing.counterpart.id == opponent.id
    assert outgoing.direction == :outgoing
    assert outgoing.contact_request?
    assert outgoing.can_cancel?
    refute outgoing.can_accept?
    refute outgoing.can_decline?
    refute outgoing.can_respond?

    assert {:ok, opponent_hub} = Play.activity_hub_state(opponent)
    incoming = Enum.find(opponent_hub.open_encounters, &(&1.id == outgoing.id))
    assert incoming.direction == :incoming
    assert incoming.can_accept?
    assert incoming.can_decline?
    refute incoming.can_cancel?
    refute incoming.can_respond?

    assert {:error, :contact_request_not_found} =
             Play.respond_to_traveler_contact(observer, outgoing.id, :accept)

    assert {:error, %Ecto.Changeset{} = role_changeset} =
             Play.respond_to_traveler_contact(character, outgoing.id, :accept)

    assert %{status: ["only the requested traveler may answer"]} = errors_on(role_changeset)

    assert {:error, :invalid_contact_decision} =
             Play.respond_to_traveler_contact(opponent, outgoing.id, "trade")

    assert {:error, :contact_request_not_found} =
             Play.respond_to_traveler_contact(opponent, "not-a-uuid", "accept")
  end

  test "contact target can accept after leaving the request location", %{
    tower: tower,
    character: character,
    opponent: opponent
  } do
    assert {:ok, %{encounter: outgoing}} =
             Play.request_traveler_contact(character.id, opponent.id)

    moved_opponent =
      opponent
      |> Character.travel_changeset(%{current_location_id: tower.id})
      |> Repo.update!()

    assert {:ok, moved_hub} = Play.activity_hub_state(moved_opponent)
    assert Enum.any?(moved_hub.open_encounters, &(&1.id == outgoing.id and &1.can_accept?))

    assert {:ok, %{encounter: accepted, decision: :accept}} =
             Play.respond_to_traveler_contact(moved_opponent.id, outgoing.id, "accept")

    assert accepted.status == :greeted
    assert accepted.direction == :incoming
    refute accepted.can_accept?
    refute accepted.can_decline?
    refute accepted.can_cancel?
  end

  test "scavenging facade only starts a current-location available cache", %{
    city: city,
    character: character
  } do
    {:ok, cache} =
      Scavenging.ensure_resource_cache(city, %{
        resource_code: "facade_scraps",
        quantity_total: 2,
        quantity_remaining: 2,
        respawn_game_days: 7
      })

    assert {:error, :resource_cache_not_found} =
             Play.start_scavenging(character, "missing-cache", 1)

    assert {:ok, %{attempt: attempt, resource_cache: updated_cache}} =
             Play.start_scavenging(character, cache.id, 1)

    assert attempt.resource_code == "facade_scraps"
    assert updated_cache.quantity_remaining == 1
  end

  test "dungeon harvesting facade returns the persisted time and XP result", %{
    realm: realm,
    tower: tower,
    character: character
  } do
    character = move_to(character, tower)

    assert {:ok, dungeon} =
             Dungeons.create_dungeon(realm, %{
               slug: "facade-harvest-dungeon",
               name: "Facade Harvest Dungeon",
               status: :active,
               entrance_location_id: tower.id
             })

    assert {:ok, floor} = Dungeons.create_floor(dungeon, %{number: 1, name: "Entrance Floor"})

    assert {:ok, _entrance} =
             Dungeons.create_node(floor, %{
               slug: "facade-harvest-entrance",
               name: "Harvest Entrance",
               kind: :entrance,
               x: 0,
               y: 0,
               threat_level: 0
             })

    assert {:ok, %{party: party}} = Parties.create_party(character, %{name: "Facade Delvers"})
    assert {:ok, %{expedition: _expedition}} = Parties.start_expedition(party)
    assert {:ok, before_harvest} = Play.enter_current_dungeon(character)

    [resource] = before_harvest.available_resources

    assert {:ok, after_harvest} =
             Play.harvest_current_dungeon_resource(character, resource.id, 1)

    assert after_harvest.run.metadata["scavenging_game_days"] == 1
    assert after_harvest.survival.food_units_consumed == 1
    assert after_harvest.survival.food_units_remaining == 19
    assert after_harvest.available_resources == []
    assert Repo.get!(Character, character.id).xp == 3
  end

  test "inventory_state/1 composes carried items and capacity for the web", %{
    character: character
  } do
    assert {:ok, state} = Play.inventory_state(character.id)

    assert state.character.id == character.id
    assert state.current_location.slug == "capital-city"
    assert [%{item_template: %{code: "travel_ration"}, quantity: 20}] = state.items
    assert Enum.all?(state.available_quantities, fn {_item_id, quantity} -> quantity >= 0 end)
    assert state.active_grimoire == nil
    assert state.food_units == 20
    assert state.carried_weight == 20
    assert state.carry_capacity > state.carried_weight
  end

  test "the trained Tower circle compiles the reported six-seal formula with an owned foundation",
       %{
         character: character,
         tower: tower
       } do
    character =
      character
      |> move_to(tower)
      |> Character.changeset(%{metadata: %{"progression_tier" => "legendary"}})
      |> Repo.update!()

    base_spell = spell_fixture(character, "Ember Spark")

    assert {:ok, compiled_spell} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Permutatio",
               "forma" => "Nexus",
               "vis" => "Enormis",
               "tempus" => "Sustineo",
               "mutatio" => "Motus",
               "pretium" => "Sanguis",
               "base" => base_spell.id,
               "formula" => "эта строка никогда не должна попасть в компилятор"
             })

    assert compiled_spell.creator_character_id == character.id
    assert compiled_spell.source_spell_id == base_spell.id
    assert compiled_spell.formula == "Permutatio Nexus Enormis Sustineo Motus Sanguis"

    assert compiled_spell.incantation_slots == %{
             "actio" => "Permutatio",
             "forma" => "Nexus",
             "vis" => "Enormis",
             "tempus" => "Sustineo",
             "mutatio" => "Motus",
             "pretium" => "Sanguis"
           }

    assert Repo.aggregate(Request, :count, :id) == 1

    request = Repo.one!(Request)
    prompt_payload = Jason.decode!(request.request_payload["user_prompt"])

    assert prompt_payload["request"]["incantation_slots"] == %{
             "actio" => "Permutatio",
             "forma" => "Nexus",
             "vis" => "Enormis",
             "tempus" => "Sustineo",
             "mutatio" => "Motus",
             "pretium" => "Sanguis"
           }

    assert prompt_payload["base_spell"]["id"] == base_spell.id
  end

  test "the trained Tower circle can create an independent spell without a foundation", %{
    character: character,
    tower: tower
  } do
    character =
      character
      |> move_to(tower)
      |> Character.changeset(%{metadata: %{"progression_tier" => "legendary"}})
      |> Repo.update!()

    assert {:ok, compiled_spell} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Vocatio",
               "tempus" => "Sustineo",
               "base" => "   "
             })

    assert compiled_spell.creator_character_id == character.id
    assert compiled_spell.source_spell_id == nil
    assert compiled_spell.formula == "Vocatio Sustineo"

    assert compiled_spell.incantation_slots == %{
             "actio" => "Vocatio",
             "tempus" => "Sustineo"
           }

    assert Repo.aggregate(Request, :count, :id) == 1

    request = Repo.one!(Request)
    prompt_payload = Jason.decode!(request.request_payload["user_prompt"])

    assert prompt_payload["request"]["incantation_slots"] == %{
             "actio" => "Vocatio",
             "tempus" => "Sustineo"
           }
  end

  test "an untrained caster receives the strict three-seal circle and can create a root spell", %{
    character: character,
    tower: tower
  } do
    character = move_to(character, tower)

    assert {:ok, state} = Play.spellbook_state(character)
    assert state.spell_circle_tier == :novice

    assert Enum.sort(state.permitted_schools) ==
             Enum.sort(~w(fire water earth air life death chaos order))

    assert {:ok, spell} =
             Play.compile_structured_spell(character, %{
               "school" => "water",
               "actio" => "Captio",
               "tempus" => "Momentum",
               "forma" => "Sphaera",
               "formula" => "untrusted ready-made formula"
             })

    assert spell.formula == "Captio Momentum"
    assert spell.incantation_slots == %{"actio" => "Captio", "tempus" => "Momentum"}
    assert spell.school == :water
    assert spell.source_spell_id == nil
    assert Repo.aggregate(Request, :count, :id) == 1
  end

  test "an Arena profile composes immediately from exactly its three schools and creates free drafts",
       %{tower: tower} do
    account =
      %Account{}
      |> Account.registration_changeset(%{
        display_name: "Arena Spellwright",
        handle: "arena-spellwright"
      })
      |> Repo.insert!()

    assert {:ok, profile} =
             Arena.create_profile(account, %{
               name: "Arena Spellwright",
               schools: [:fire, :life, :order]
             })

    assert profile.character.current_location_id == tower.id
    assert {:ok, state} = Play.spellbook_state(profile.character)
    assert state.arena_mode?
    assert state.spell_circle_tier == :trained
    assert state.permitted_schools == ["fire", "life", "order"]
    assert state.composition_available?

    assert {:error, :school_not_permitted} =
             Play.compile_structured_spell(profile.character, %{
               "school" => "water",
               "actio" => "Aqua"
             })

    assert {:ok, %{attempt: attempt}} =
             Play.begin_spell_creation(profile.character, %{
               "school" => "life",
               "actio" => "Vocatio",
               "tempus" => "Sustineo"
             })

    assert attempt.status == :revealed
    assert attempt.completes_at == attempt.started_at
    assert attempt.outcome["kind"] == "success"
    assert Creation.active_attempt(profile.character_id) == nil

    assert {:ok, summoned_spell} =
             Play.spell_creation_result(profile.character, attempt.id)

    assert summoned_spell.school == :life
    assert summoned_spell.manifestation.kind == :creature_ally

    assert {:ok, draft} = Play.create_arena_draft_grimoire(profile.character)
    assert draft.status == :draft
    assert draft.capacity == Arena.grimoire_capacity()
    assert draft.weight == 0
    assert draft.metadata["free"] == true

    assert {:ok, entry} =
             Play.inscribe_spell(profile.character, draft.id, summoned_spell.id)

    assert entry.spell_id == summoned_spell.id

    assert {:ok, %{activate_grimoire: active}} =
             Play.activate_grimoire(profile.character, draft.id)

    assert active.id == draft.id
    assert Grimoires.active_grimoire_for_character(profile.character_id).id == draft.id
  end

  test "a known same-school spell is not silently attached to the novice circle", %{
    character: character,
    tower: tower
  } do
    character = move_to(character, tower)
    spell_fixture(character, "Known Tower Spark")

    assert {:ok, spell} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Ignis",
               "tempus" => "Momentum"
             })

    assert spell.source_spell_id == nil
    assert spell.power == 1
    assert spell.fatigue_cost <= 12
    assert spell.cooldown_turns <= 3
    assert spell.environment_mode == :none
    assert spell.environment_tags == []
    assert spell.interaction_rules == []

    assert [effect] = spell.effects
    assert effect.applies_to != :environment
    assert effect.intensity <= 12
    assert effect.variance <= 2
    assert effect.duration <= 3
  end

  test "the novice circle requires one bounded word in both Actio and Tempus", %{
    character: character,
    tower: tower
  } do
    character = move_to(character, tower)

    assert {:error, :incomplete_spell_circle} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Ictus"
             })

    assert {:error, :invalid_spell_circle_word} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Ictus Magnus",
               "tempus" => "Momentum"
             })

    assert {:error, :invalid_spell_circle_word} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Удар",
               "tempus" => "Momentum"
             })

    assert {:error, :invalid_spell_circle} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => <<255>>,
               "tempus" => "Momentum"
             })

    assert {:error, :invalid_spell_circle} = Play.compile_structured_spell(character, "Ignis")
    assert Repo.aggregate(Request, :count, :id) == 0
  end

  test "resolution recovery rechecks the ritual location before sealing a hidden spell", %{
    character: character,
    city: city,
    tower: tower
  } do
    character = move_to(character, tower)

    assert {:ok, %{attempt: attempt}} =
             Play.begin_spell_creation(character, %{
               "school" => "fire",
               "actio" => "Ignis",
               "tempus" => "Momentum"
             })

    assert {:ok, %{action: :resolve}} = Creation.claim_resolution(attempt.id)

    assert {:ok, hidden_spell} =
             Spells.create_spell(
               character,
               %{
                 name: "Скрытая искра",
                 formula: "Ignis Momentum",
                 incantation_slots: %{"actio" => "Ignis", "tempus" => "Momentum"},
                 school: :fire,
                 description: "Заклинание ещё удерживается незавершённым ритуалом.",
                 targeting: :enemy,
                 delivery_form: :sphere,
                 effects: [
                   %{
                     applies_to: :target,
                     state: "impact",
                     intensity: 10,
                     variance: 0,
                     duration: 0
                   }
                 ],
                 failure_profile: %{
                   difficulty: 5,
                   base_success_rate: 90,
                   partial_success_rate: 5
                 }
               },
               creation_attempt_id: attempt.id
             )

    _moved_character = move_to(character, city)

    assert :ok = Play.resolve_spell_creation_attempt(attempt.id)

    recovered_attempt = Creation.get_attempt(attempt.id)
    assert recovered_attempt.status == :sealed_failure
    assert recovered_attempt.outcome["code"] == "spellbook_location"
    assert Repo.get(Spell, hidden_spell.id) == nil
  end

  test "spellbook composition rejects a city without an active player base before creating an AI request",
       %{
         character: character
       } do
    base_spell = spell_fixture(character, "City Spark")

    assert {:error, :spellbook_location} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Ignis",
               "tempus" => "Momentum",
               "base" => base_spell.id
             })

    assert Repo.aggregate(Request, :count, :id) == 0
  end

  test "spellbook composition rejects an active journey before creating an AI request", %{
    character: character,
    tower: tower
  } do
    base_spell = spell_fixture(character, "Journey Spark")
    assert {:ok, %{journey: journey}} = Play.start_journey(character.id, tower.slug)
    assert journey.status == :active

    assert {:error, :travelling} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Ignis",
               "tempus" => "Momentum",
               "base" => base_spell.id
             })

    assert Repo.aggregate(Request, :count, :id) == 0
  end

  test "spellbook composition rejects foreign bases and disallowed schools before AI execution",
       %{
         realm: realm,
         character: character,
         tower: tower
       } do
    character =
      character
      |> move_to(tower)
      |> Character.changeset(%{metadata: %{"progression_tier" => "legendary"}})
      |> Repo.update!()

    own_base = spell_fixture(character, "Owned Tower Spark")
    foreign_character = character_fixture(realm, tower, "foreign-compiler", "Foreign Compiler")
    foreign_base = spell_fixture(foreign_character, "Foreign Tower Spark")

    assert {:error, _changeset} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Ignis",
               "base" => foreign_base.id
             })

    assert {:error, :invalid_spell_circle} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Ignis",
               "base" => %{"id" => own_base.id}
             })

    assert {:error, :school_not_permitted} =
             Play.compile_structured_spell(character, %{
               "school" => "water",
               "actio" => "Aqua",
               "base" => own_base.id
             })

    assert Repo.aggregate(Request, :count, :id) == 0
  end

  test "spellbook inscriptions use the selected owned spell and reject foreign books and spells",
       %{
         realm: realm,
         character: character,
         tower: tower
       } do
    character = move_to(character, tower)
    selected_spell = spell_fixture(character, "Selected Tower Spell")

    assert {:ok, own_grimoire} =
             Grimoires.create_grimoire(character, %{name: "Tower Draft", capacity: 3, weight: 1})

    foreign_character = character_fixture(realm, tower, "foreign-scribe", "Foreign Scribe")
    foreign_spell = spell_fixture(foreign_character, "Foreign Inscription")

    assert {:ok, foreign_grimoire} =
             Grimoires.create_grimoire(foreign_character, %{
               name: "Foreign Draft",
               capacity: 3,
               weight: 1
             })

    assert {:ok, entry} = Play.inscribe_spell(character, own_grimoire.id, selected_spell.id)
    assert entry.spell_id == selected_spell.id

    assert {:error, :grimoire_not_found} =
             Play.inscribe_spell(character, foreign_grimoire.id, selected_spell.id)

    assert {:error, :spell_not_found} =
             Play.inscribe_spell(character, own_grimoire.id, foreign_spell.id)
  end

  test "spellbook activation is gated at a city and while travelling", %{
    character: character,
    tower: tower
  } do
    assert {:ok, grimoire} =
             Grimoires.create_grimoire(character, %{name: "Gated Draft", capacity: 3, weight: 1})

    assert {:error, :spellbook_location} = Play.activate_grimoire(character, grimoire.id)
    assert Grimoires.get_grimoire!(grimoire.id).status == :draft

    assert {:ok, %{journey: journey}} = Play.start_journey(character.id, tower.slug)
    assert journey.status == :active
    assert {:error, :travelling} = Play.activate_grimoire(character, grimoire.id)
    assert Grimoires.get_grimoire!(grimoire.id).status == :draft
  end

  test "spellbook inscription is gated at a city and while travelling", %{
    character: character,
    tower: tower
  } do
    spell = spell_fixture(character, "Gated Inscription")

    assert {:ok, grimoire} =
             Grimoires.create_grimoire(character, %{
               name: "Unwritten Draft",
               capacity: 3,
               weight: 1
             })

    assert {:error, :spellbook_location} =
             Play.inscribe_spell(character, grimoire.id, spell.id)

    assert Grimoires.get_grimoire!(grimoire.id).entries == []

    assert {:ok, %{journey: journey}} = Play.start_journey(character.id, tower.slug)
    assert journey.status == :active

    assert {:error, :travelling} = Play.inscribe_spell(character, grimoire.id, spell.id)
    assert Grimoires.get_grimoire!(grimoire.id).entries == []
  end

  test "an active owned city base permits spellbook state and composition", %{
    character: character,
    city: city
  } do
    base_spell = spell_fixture(character, "Basebound Spark")
    fund_base_acquisition!(city.realm_id |> Worlds.get_realm!(), character)
    assert {:ok, _base} = Bases.purchase_city_base(character, city)

    assert {:ok, state} = Play.spellbook_state(character)
    assert state.composition_location.id == city.id
    assert state.composition_location.kind == :city
    assert state.permitted_schools == ["fire"]

    assert {:ok, compiled_spell} =
             Play.compile_structured_spell(character, %{
               "school" => "fire",
               "actio" => "Ignis",
               "tempus" => "Vinculum",
               "base" => base_spell.id
             })

    assert compiled_spell.source_spell_id == nil
    assert Repo.aggregate(Request, :count, :id) == 1
  end

  test "known_spells_and_duel_state/2 summarizes spells and duel state", %{
    tower: tower,
    character: character,
    opponent: opponent
  } do
    character = move_to(character, tower)
    opponent = move_to(opponent, tower)

    {:ok, spell} =
      Spells.create_spell(character, %{
        name: "Ignis Sphaera",
        formula: "Ignis Sphaera Magnus",
        school: :fire,
        description: "A compiled fire sphere.",
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 18, variance: 2, duration: 0}
        ],
        failure_profile: %{difficulty: 20, base_success_rate: 86, partial_success_rate: 8}
      })

    assert {:ok, pending_duel} = PVP.challenge_duel(character, opponent, 25)

    assert {:ok, summary} = Play.known_spells_and_duel_state(character.id, opponent.id)

    assert [%{id: spell_id}] = summary.spells
    assert spell_id == spell.id
    assert summary.duel.opponent.id == opponent.id
    assert [%{id: duel_id, status: :pending}] = summary.duel.pending_duels
    assert duel_id == pending_duel.id
  end

  test "the duel facade accepts the local opponent and only casts prepared spells", %{
    realm: realm,
    tower: tower,
    character: character,
    opponent: opponent
  } do
    character = move_to(character, tower)
    opponent = move_to(opponent, tower)
    {:ok, _character_funds} = Economy.grant_from_treasury(realm, character, 200)
    {:ok, _opponent_funds} = Economy.grant_from_treasury(realm, opponent, 200)

    {:ok, spell} =
      Spells.create_spell(character, %{
        name: "Facade Ultima",
        formula: "Ignis Ultima Suprema",
        school: :fire,
        description: "A deterministic facade test spell.",
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 100, variance: 0, duration: 0}
        ],
        failure_profile: %{
          difficulty: 5,
          base_success_rate: 100,
          partial_success_rate: 0,
          backlash_damage: 0
        }
      })

    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: "Facade Grimoire", capacity: 5, weight: 1})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)
    {:ok, %{activate_grimoire: _grimoire}} = Grimoires.activate_grimoire(character, grimoire)

    assert {:ok, state} = Play.start_demo_duel(character.id, opponent.id)
    assert state.duel.status == :active
    assert [%{id: spell_id}] = state.prepared_spells
    assert spell_id == spell.id

    assert {:error, :spell_not_prepared} =
             Play.cast_and_resolve_duel_turn(character.id, opponent.id)

    assert {:ok, resolved_state} = Play.cast_and_resolve_duel_turn(character.id, spell.id)
    assert resolved_state.duel.status == :resolved
    assert resolved_state.duel.winner_character_id == character.id
  end

  test "combat state and action submission stay inside the current participant scope", %{
    realm: realm,
    tower: tower,
    character: character,
    opponent: opponent
  } do
    character = move_to(character, tower)
    opponent = move_to(opponent, tower)
    observer = character_fixture(realm, tower, "combat-observer", "Combat Observer")
    {:ok, _character_funds} = Economy.grant_from_treasury(realm, character, 200)
    {:ok, _opponent_funds} = Economy.grant_from_treasury(realm, opponent, 200)
    spell = spell_fixture(character, "Scoped Combat Spell")

    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: "Scoped Grimoire", capacity: 5, weight: 1})

    {:ok, _entry} = Grimoires.inscribe_spell(grimoire, spell)
    {:ok, _active_grimoire} = Grimoires.activate_grimoire(character, grimoire)

    assert {:ok, started_state} = Play.start_demo_duel(character, opponent.id)
    assert started_state.own_action == nil
    assert started_state.action_open?
    assert started_state.submitted_action_count == 1

    assert {:ok, spectator_state} = Play.combat_state(observer, started_state.combat.id)
    assert spectator_state.spectator?

    assert {:error, :spectator} =
             Play.submit_combat_action(observer, started_state.combat.id, %{action_type: :wait})

    assert {:ok, sealed_state} =
             Play.submit_combat_action(character, started_state.combat.id, %{
               "action_type" => "cast_spell",
               "spell_id" => spell.id,
               "target_side" => "defenders"
             })

    assert sealed_state.own_action.action_type == :cast_spell
    assert sealed_state.resolving?
    refute sealed_state.action_open?
  end

  test "ensure_demo_character_usable/2 activates and stocks a demo character", %{
    city: city,
    character: character
  } do
    inactive =
      character
      |> Character.changeset(%{status: :frozen})
      |> Repo.update!()
      |> Character.travel_changeset(%{current_location_id: nil})
      |> Repo.update!()

    assert {:ok, usable} = Play.ensure_demo_character_usable(inactive.id, city)

    assert usable.status == :active
    assert usable.current_location_id == city.id
    assert usable.current_location.id == city.id
    assert MMGO.Survival.food_units_available(usable) >= 30
  end

  test "start_new_local_session/0 creates a character with the full starter kit", %{city: city} do
    assert {:ok, %{challenger: character, opponent: opponent}} = Play.start_new_local_session()

    assert character.status == :active
    assert character.realm_id == city.realm_id
    assert character.current_location_id == city.id
    assert opponent.current_location_id == city.id

    assert Repo.get_by!(EconomyAccount, character_id: character.id).current_balance == 1_000
    assert MMGO.Survival.food_units_available(character) >= 30

    inventory =
      character.id
      |> Inventory.list_inventory_for_character()
      |> Enum.map(& &1.item_template.code)

    assert "demo_travel_ration" in inventory
    assert "demo_lumen_dust" in inventory

    assert [%{name: "Искра углей"}] = Spells.list_spells_for_character(character.id)
    assert %{status: :active} = Grimoires.active_grimoire_for_character(character.id)
  end

  test "continue_local_session/0 preserves local progress while reset rebuilds it", %{
    tower: tower
  } do
    assert {:ok, %{challenger: character, opponent: opponent}} = Play.start_new_local_session()
    character = move_to(character, tower)
    opponent = move_to(opponent, tower)
    {:ok, duel} = PVP.challenge_duel(character, opponent, 25)
    {:ok, %{journey: journey}} = Play.start_journey(character.id, "capital-city")

    {:ok, account} = Economy.ensure_character_account(character)
    account |> EconomyAccount.changeset(%{current_balance: 2_500}) |> Repo.update!()

    assert {:ok, %{challenger: continued}} = Play.continue_local_session()
    assert continued.id == character.id
    assert Repo.get_by!(EconomyAccount, character_id: continued.id).current_balance == 2_500
    assert Travel.active_journey(continued.id).id == journey.id

    assert {:ok, %{challenger: reset}} = Play.reset_demo_session()
    assert reset.id == character.id
    assert reset.current_location_id != tower.id
    assert Travel.active_journey(reset.id) == nil
    assert Repo.get_by!(EconomyAccount, character_id: reset.id).current_balance == 1_000
    assert Repo.get!(Journey, journey.id).status == :cancelled
    assert PVP.get_duel!(duel.id).status == :cancelled
    assert PVP.pending_duels_for_character(reset.id) == []

    assert Repo.aggregate(
             from(item in InventoryItem, where: item.character_id == ^reset.id),
             :count
           ) >= 2

    assert [%{name: "Искра углей"}] = Spells.list_spells_for_character(reset.id)
  end

  test "start_new_local_session/0 funds characters through a real treasury transfer", %{
    realm: realm
  } do
    assert {:ok, %{challenger: character, opponent: opponent}} = Play.start_new_local_session()

    treasury = Economy.treasury_account_for_realm(realm.id)
    character_account = Repo.get_by!(EconomyAccount, character_id: character.id)
    opponent_account = Repo.get_by!(EconomyAccount, character_id: opponent.id)

    assert character_account.current_balance == 1_000
    assert opponent_account.current_balance == 1_000

    # Treasury supply must have actually decreased -- money moved, it wasn't
    # conjured out of nothing.
    assert treasury.current_balance == 100_000 - 1_000 - 1_000

    ledger_entries = Economy.list_ledger_entries_for_realm(realm.id)

    assert Enum.any?(ledger_entries, fn entry ->
             entry.debit_account_id == treasury.id and
               entry.credit_account_id == character_account.id and
               entry.amount == 1_000
           end)

    assert Enum.any?(ledger_entries, fn entry ->
             entry.debit_account_id == treasury.id and
               entry.credit_account_id == opponent_account.id and
               entry.amount == 1_000
           end)
  end

  test "reset_demo_session/0 refunds an active duel's escrow instead of stranding it", %{
    realm: realm,
    tower: tower
  } do
    assert {:ok, %{challenger: character, opponent: opponent}} = Play.start_new_local_session()

    character = move_to(character, tower)
    opponent = move_to(opponent, tower)

    {:ok, duel} = PVP.challenge_duel(character, opponent, 100)
    {:ok, accepted_duel} = PVP.accept_duel(duel, opponent)

    escrow_account = Economy.get_account!(accepted_duel.escrow_account_id)
    assert escrow_account.current_balance == 200

    assert {:ok, _session} = Play.reset_demo_session()

    resolved_duel = PVP.get_duel!(duel.id)
    assert resolved_duel.status == :cancelled

    # The escrow must be drained back to the participants -- not left funded
    # forever with a cancelled duel sitting on top of it.
    refreshed_escrow = Economy.get_account!(accepted_duel.escrow_account_id)
    assert refreshed_escrow.current_balance == 0

    ledger_entries = Economy.list_ledger_entries_for_realm(realm.id)

    assert Enum.count(ledger_entries, fn entry ->
             entry.debit_account_id == escrow_account.id and entry.amount == 100
           end) == 2
  end

  test "reset_demo_session/0 zeroes the balance through a real transfer back to treasury", %{
    realm: realm
  } do
    assert {:ok, %{challenger: character}} = Play.start_new_local_session()

    {:ok, account} = Economy.ensure_character_account(character)
    account |> EconomyAccount.changeset(%{current_balance: 2_500}) |> Repo.update!()

    treasury_before = Economy.treasury_account_for_realm(realm.id)

    assert {:ok, %{challenger: reset}} = Play.reset_demo_session()

    assert Repo.get_by!(EconomyAccount, character_id: reset.id).current_balance == 1_000

    treasury_after = Economy.treasury_account_for_realm(realm.id)

    # The 2_500 balance must have actually landed back in the treasury via a
    # transfer, not simply vanished via a bare balance write.
    assert treasury_after.current_balance == treasury_before.current_balance + 2_500 - 1_000

    ledger_entries = Economy.list_ledger_entries_for_realm(realm.id)

    assert Enum.any?(ledger_entries, fn entry ->
             entry.credit_account_id == treasury_after.id and entry.amount == 2_500
           end)
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

  defp spell_fixture(character, name, attrs \\ %{}) do
    defaults = %{
      name: name,
      formula: "Ignis Minima",
      school: :fire,
      description: "A spell owned by the Play facade test caster.",
      targeting: :enemy,
      delivery_form: :sphere,
      effects: [
        %{applies_to: :target, state: "impact", intensity: 10, variance: 0, duration: 0}
      ],
      failure_profile: %{difficulty: 5, base_success_rate: 90, partial_success_rate: 5}
    }

    {:ok, spell} = Spells.create_spell(character, Map.merge(defaults, attrs))
    spell
  end

  defp move_to(character, location) do
    character
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
