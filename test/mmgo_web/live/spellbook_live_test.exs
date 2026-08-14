defmodule MMGOWeb.SpellbookLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.Accounts.{Account, Character}
  alias MMGO.Arena
  alias MMGO.Bases.Base
  alias MMGO.Grimoires
  alias MMGO.Play
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Spells.{Creation, CreationAttempt, ResolveCreationAttemptWorker}
  alias MMGO.Travel.Journey
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{slug: "canonical", name: "Canonical Realm", is_default: true})

    {:ok, capital_city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 960,
        y: 1040,
        safe_zone: true
      })

    {:ok, the_tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 100,
        y: 100,
        safe_zone: false
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Tower Road",
        origin_location_id: capital_city.id,
        destination_location_id: the_tower.id,
        travel_days: 2,
        risk_level: 10,
        bidirectional: true
      })

    character = character_fixture(realm, capital_city, "spellcaster", "Spellcaster")
    base_spell = spell_fixture(character, "Ignis Prima", "Ignis Prima", :fire)

    {:ok, grimoire} =
      Grimoires.create_grimoire(character, %{name: "Дорожный гримуар", capacity: 3, weight: 2})

    %{
      realm: realm,
      capital_city: capital_city,
      the_tower: the_tower,
      route: route,
      character: character,
      base_spell: base_spell,
      grimoire: grimoire
    }
  end

  test "unauthenticated visitors are redirected to /play", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/play"}}} = live(conn, ~p"/spellbook")
  end

  test "a character outside a Tower or owned base can read but not change the spellbook", %{
    conn: conn,
    character: character
  } do
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    assert has_element?(view, "#spellbook-screen")
    assert has_element?(view, "#spell-compose-locked")
    assert has_element?(view, "#spellbook-read-only-note")
    refute has_element?(view, "#spell-circle-root")
    refute has_element?(view, "#spell-compose-form")
  end

  test "an Arena spellbook is immediate, restricted to three schools, and issues free drafts", %{
    conn: conn
  } do
    account =
      %Account{}
      |> Account.registration_changeset(%{
        display_name: "Arena Scribe",
        handle: "arena-scribe-live"
      })
      |> Repo.insert!()

    assert {:ok, profile} =
             Arena.create_profile(account, %{
               name: "Arena Scribe",
               schools: [:fire, :life, :order]
             })

    {:ok, view, _html} =
      live(arena_session_conn(conn, account, profile.character), ~p"/arena/spellbook")

    assert has_element?(view, "#spellbook-screen")
    assert has_element?(view, "#spellbook-back-to-map[href='/arena']")
    assert has_element?(view, "#spell-circle-root[data-circle-tier='trained']")

    render_hook(view, "hook_mounted", %{"hook" => "SpellCircle"})

    assert_push_event(view, "spell_circle_init", %{
      slots: slots,
      current: %{},
      ritual_duration_ms: 0,
      ritual: %{active: false, remaining_ms: 0}
    })

    school_slot = Enum.find(slots, &(&1.key == "school"))
    assert Enum.map(school_slot.options, & &1.value) == ["fire", "life", "order"]

    render_hook(view, "spell_compile", %{
      "school" => "life",
      "actio" => "Vocatio",
      "tempus" => "Sustineo"
    })

    summoned_spell =
      profile.character_id
      |> Spells.list_spells_for_character()
      |> Enum.find(&(&1.formula == "Vocatio Sustineo"))

    assert summoned_spell
    assert summoned_spell.manifestation.kind == :creature_ally
    assert Creation.active_attempt(profile.character_id) == nil
    assert has_element?(view, "#spell-compose-result-#{summoned_spell.id}")
    assert has_element?(view, "#spell-compose-manifestation-#{summoned_spell.id}")

    {:ok, library, _html} =
      live(arena_session_conn(conn, account, profile.character), ~p"/arena/spellbook/library")

    assert has_element?(library, "#spell-manifestation-#{summoned_spell.id}")

    {:ok, view, _html} =
      live(arena_session_conn(conn, account, profile.character), ~p"/arena/spellbook/books")

    assert has_element?(view, "#create-arena-grimoire")
    assert has_element?(view, "#arena-grimoire-policy")
    initial_count = length(Grimoires.list_grimoires_for_character(profile.character_id))

    view
    |> element("#create-arena-grimoire")
    |> render_click()

    grimoires = Grimoires.list_grimoires_for_character(profile.character_id)
    assert length(grimoires) == initial_count + 1
    assert Enum.any?(grimoires, &(&1.status == :draft and &1.capacity == 15 and &1.weight == 0))
  end

  test "the novice circle has exactly three seals and compiles at the Tower", %{
    conn: conn,
    character: character,
    the_tower: the_tower,
    base_spell: _base_spell
  } do
    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    assert has_element?(
             view,
             "#spell-circle-root[phx-hook='SpellCircle'][data-circle-tier='novice']"
           )

    assert has_element?(view, "#spell-circle-instruction")
    refute has_element?(view, "#spell-compose-form")
    refute render(view) =~ "Записать формулу пером"

    render_hook(view, "hook_mounted", %{"hook" => "SpellCircle"})

    assert_push_event(view, "spell_circle_init", %{
      slots: slots,
      current: %{},
      ritual_duration_ms: 10_000,
      ritual: %{active: false, remaining_ms: 0}
    })

    assert Enum.map(slots, & &1.key) == ["school", "actio", "tempus"]
    assert Enum.map(slots, & &1.label) == ["Schola", "Actio", "Tempus"]
    assert Enum.all?(slots, & &1.required)

    render_hook(view, "spell_compile", %{
      "school" => "fire",
      "actio" => "Ignis",
      "tempus" => "Momentum"
    })

    assert %{status: :queued} = Creation.active_attempt(character.id)

    assert is_nil(
             Enum.find(
               Spells.list_spells_for_character(character.id),
               &(&1.formula == "Ignis Momentum")
             )
           )

    assert %{status: :revealed, outcome: %{"kind" => "success"}} =
             resolve_and_reveal_ritual(view, character)

    compiled_spell =
      character.id
      |> Spells.list_spells_for_character()
      |> Enum.find(&(&1.formula == "Ignis Momentum"))

    assert compiled_spell.source_spell_id == nil
    assert has_element?(view, "#spell-compose-result-#{compiled_spell.id}")

    {:ok, library, _html} = live(session_conn(conn, character), ~p"/spellbook/library")

    assert has_element?(library, "#spell-library-#{compiled_spell.id}")
  end

  test "a novice with an empty library can create a root spell", %{
    conn: conn,
    realm: realm,
    the_tower: the_tower
  } do
    root_character =
      character_fixture(realm, the_tower, "root-caster", "Root Caster")

    {:ok, view, _html} = live(session_conn(conn, root_character), ~p"/spellbook")

    assert has_element?(view, "#spell-circle-root[data-circle-tier='novice']")
    refute has_element?(view, "#spell-library-empty")

    render_hook(view, "spell_compile", %{
      "school" => "air",
      "actio" => "Ictus",
      "tempus" => "Momentum"
    })

    assert %{status: :revealed, outcome: %{"kind" => "success"}} =
             resolve_and_reveal_ritual(view, root_character)

    compiled_spell =
      root_character.id
      |> Spells.list_spells_for_character()
      |> Enum.find(&(&1.formula == "Ictus Momentum"))

    assert compiled_spell.source_spell_id == nil
    assert has_element?(view, "#spell-compose-result-#{compiled_spell.id}")
  end

  test "reload restores one durable ritual without revealing or duplicating it", %{
    conn: conn,
    character: character,
    the_tower: the_tower
  } do
    character = move_to(character, the_tower)
    conn = session_conn(conn, character)
    {:ok, first_view, _html} = live(conn, ~p"/spellbook")

    render_hook(first_view, "spell_compile", %{
      "school" => "fire",
      "actio" => "Ictus",
      "tempus" => "Momentum"
    })

    attempt = Creation.active_attempt(character.id)
    assert attempt.status == :queued

    assert Spells.list_spells_for_character(character.id) |> Enum.map(& &1.formula) == [
             "Ignis Prima"
           ]

    {:ok, restored_view, _html} = live(conn, ~p"/spellbook")
    render_hook(restored_view, "hook_mounted", %{"hook" => "SpellCircle"})

    assert_push_event(restored_view, "spell_circle_init", %{
      current: %{"school" => "fire", "actio" => "Ictus", "tempus" => "Momentum"},
      ritual: %{active: true, remaining_ms: remaining_ms},
      ritual_duration_ms: 10_000
    })

    assert remaining_ms in 0..10_000

    render_hook(restored_view, "spell_compile", %{
      "school" => "air",
      "actio" => "Captio",
      "tempus" => "Momentum"
    })

    assert Repo.aggregate(CreationAttempt, :count, :id) == 1
    assert Creation.active_attempt(character.id).id == attempt.id

    assert %{status: :revealed, outcome: %{"kind" => "success"}} =
             resolve_and_reveal_ritual(restored_view, character)

    assert Enum.any?(Spells.list_spells_for_character(character.id), fn spell ->
             spell.formula == "Ictus Momentum"
           end)
  end

  test "a revealed failure is restored after the player reconnects", %{
    conn: conn,
    character: character,
    the_tower: the_tower
  } do
    character = move_to(character, the_tower)

    assert {:ok, %{attempt: attempt}} =
             Play.begin_spell_creation(character, %{
               "school" => "fire",
               "actio" => "",
               "tempus" => ""
             })

    assert :ok =
             ResolveCreationAttemptWorker.perform(%Oban.Job{
               args: %{"attempt_id" => attempt.id}
             })

    sealed_attempt = Creation.get_attempt(attempt.id)
    assert sealed_attempt.status == :sealed_failure

    assert {:ok, %{status: :revealed}} =
             Creation.reveal(attempt.id, now: sealed_attempt.completes_at)

    {:ok, restored_view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    assert has_element?(
             restored_view,
             "#spell-compose-error",
             "Обязательная печать осталась немой, и круг не смог замкнуться."
           )
  end

  test "a trained caster with an empty library gets an optional Fundamen", %{
    conn: conn,
    realm: realm,
    the_tower: the_tower
  } do
    trained_character =
      realm
      |> character_fixture(the_tower, "trained-root-caster", "Trained Root Caster")
      |> Character.changeset(%{metadata: %{"progression_tier" => "legendary"}})
      |> Repo.update!()

    {:ok, view, _html} = live(session_conn(conn, trained_character), ~p"/spellbook")

    assert has_element?(view, "#spell-circle-root[data-circle-tier='trained']")
    refute has_element?(view, "#spell-library-empty")

    render_hook(view, "hook_mounted", %{"hook" => "SpellCircle"})

    assert_push_event(view, "spell_circle_init", %{
      slots: slots,
      current: %{},
      ritual_duration_ms: 10_000,
      ritual: %{active: false, remaining_ms: 0}
    })

    assert Enum.map(slots, & &1.label) == [
             "Schola",
             "Actio",
             "Forma",
             "Vis",
             "Tempus",
             "Mutatio",
             "Pretium",
             "Fundamen"
           ]

    assert Enum.filter(slots, & &1.required) |> Enum.map(& &1.key) == ["school", "actio"]
    assert %{required: false, options: []} = Enum.find(slots, &(&1.key == "base"))

    render_hook(view, "spell_compile", %{
      "school" => "air",
      "actio" => "Vocatio"
    })

    assert %{status: :revealed, outcome: %{"kind" => "success"}} =
             resolve_and_reveal_ritual(view, trained_character)

    compiled_spell =
      trained_character.id
      |> Spells.list_spells_for_character()
      |> Enum.find(&(&1.formula == "Vocatio"))

    assert compiled_spell.source_spell_id == nil
    assert has_element?(view, "#spell-compose-result-#{compiled_spell.id}")
  end

  test "an active owned base permits the same form outside the Tower", %{
    conn: conn,
    character: character,
    capital_city: capital_city
  } do
    create_active_base(character, capital_city)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    assert has_element?(view, "#spell-circle-root")
    assert has_element?(view, "#spellbook-location")
  end

  test "a travelling character can read but not change the spellbook", %{
    conn: conn,
    character: character,
    realm: realm,
    route: route,
    capital_city: capital_city,
    the_tower: the_tower
  } do
    create_active_journey(character, realm, route, capital_city, the_tower)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    assert has_element?(view, "#spell-compose-locked")
    assert has_element?(view, "#spellbook-read-only-note")
    refute has_element?(view, "#spell-circle-root")
    refute has_element?(view, "#spell-compose-form")
  end

  test "the novice circle ignores forged advanced slots and foundations", %{
    conn: conn,
    realm: realm,
    character: character,
    the_tower: the_tower,
    base_spell: _base_spell
  } do
    foreign_character = character_fixture(realm, the_tower, "foreign-mage", "Foreign Mage")
    foreign_spell = spell_fixture(foreign_character, "Aqua Prima", "Aqua Prima", :water)
    character = move_to(character, the_tower)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    render_hook(view, "spell_compile", %{
      "base" => foreign_spell.id,
      "school" => "fire",
      "actio" => "Ignis",
      "tempus" => "Momentum",
      "forma" => "Injected",
      "pretium" => "Sanguis"
    })

    assert %{status: :revealed, outcome: %{"kind" => "success"}} =
             resolve_and_reveal_ritual(view, character)

    compiled_spell =
      character.id
      |> Spells.list_spells_for_character()
      |> Enum.find(&(&1.formula == "Ignis Momentum"))

    assert compiled_spell.source_spell_id == nil
    refute compiled_spell.formula =~ "Injected"
    refute compiled_spell.formula =~ "Sanguis"
  end

  test "an invalid formula is shown as a server-rendered validation error", %{
    conn: conn,
    character: character,
    the_tower: the_tower,
    base_spell: _base_spell
  } do
    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    render_hook(view, "spell_compile", %{
      "school" => "fire",
      "actio" => "Ignis 123",
      "tempus" => "Momentum"
    })

    assert %{status: :revealed, outcome: %{"kind" => "failure"}} =
             resolve_and_reveal_ritual(view, character)

    assert has_element?(
             view,
             "#spell-compose-error",
             "Одна из словесных печатей треснула: круг принимает в неё только одно латинское слово без пробелов."
           )

    assert_push_event(view, "spell_result", %{ok: false})
  end

  test "an incomplete circle resolves as a failed ritual instead of a client dead end", %{
    conn: conn,
    character: character,
    the_tower: the_tower
  } do
    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    render_hook(view, "spell_compile", %{
      "school" => "fire",
      "actio" => "",
      "tempus" => ""
    })

    assert %{status: :revealed, outcome: %{"kind" => "failure"}} =
             resolve_and_reveal_ritual(view, character)

    assert has_element?(
             view,
             "#spell-compose-error",
             "Обязательная печать осталась немой, и круг не смог замкнуться."
           )

    assert_push_event(view, "spell_result", %{ok: false})
  end

  test "a Russian compiler rejection is shown as a bounded in-world explanation", %{
    conn: conn,
    character: character,
    the_tower: the_tower
  } do
    configure_spell_provider(
      {:ok,
       %{
         "outcome" => "failed",
         "rejection_reason" =>
           "  Огонь спорит с выбранным глаголом.\nПечати не удерживают замысел.  "
       }}
    )

    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    render_hook(view, "spell_compile", %{
      "school" => "fire",
      "actio" => "Sanatio",
      "tempus" => "Momentum"
    })

    assert %{status: :revealed, outcome: %{"kind" => "failure"}} =
             resolve_and_reveal_ritual(view, character)

    assert has_element?(
             view,
             "#spell-compose-error",
             "Толкователь отверг формулу: «Огонь спорит с выбранным глаголом. Печати не удерживают замысел.»"
           )

    assert_push_event(view, "spell_result", %{ok: false})
  end

  test "a non-Russian compiler rejection never leaks raw provider prose", %{
    conn: conn,
    character: character,
    the_tower: the_tower
  } do
    configure_spell_provider(
      {:ok,
       %{
         "outcome" => "failed",
         "rejection_reason" =>
           "Ошибка: Internal provider trace: upstream shard rejected request 7f3a."
       }}
    )

    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    render_hook(view, "spell_compile", %{
      "school" => "fire",
      "actio" => "Sanatio",
      "tempus" => "Momentum"
    })

    assert %{status: :revealed, outcome: %{"kind" => "failure"}} =
             resolve_and_reveal_ritual(view, character)

    assert has_element?(
             view,
             "#spell-compose-error",
             "Толкователь отверг формулу, но письмена причины расплылись по странице. Измените сочетание печатей и попробуйте снова."
           )

    assert_push_event(view, "spell_result", %{ok: false})
  end

  test "an oversized Russian compiler rejection is replaced instead of being rendered", %{
    conn: conn,
    character: character,
    the_tower: the_tower
  } do
    configure_spell_provider(
      {:ok,
       %{
         "outcome" => "failed",
         "rejection_reason" => String.duplicate("Письмена продолжают расползаться. ", 20)
       }}
    )

    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    render_hook(view, "spell_compile", %{
      "school" => "fire",
      "actio" => "Sanatio",
      "tempus" => "Momentum"
    })

    assert %{status: :revealed, outcome: %{"kind" => "failure"}} =
             resolve_and_reveal_ritual(view, character)

    assert has_element?(
             view,
             "#spell-compose-error",
             "Толкователь отверг формулу, но письмена причины расплылись по странице. Измените сочетание печатей и попробуйте снова."
           )

    assert_push_event(view, "spell_result", %{ok: false})
  end

  test "a DeepSeek transport failure is distinguished from a bad formula", %{
    conn: conn,
    character: character,
    the_tower: the_tower
  } do
    configure_spell_provider({:error, %Req.TransportError{reason: :timeout}})

    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    render_hook(view, "spell_compile", %{
      "school" => "fire",
      "actio" => "Ictus",
      "tempus" => "Momentum"
    })

    assert %{status: :revealed, outcome: %{"kind" => "failure"}} =
             resolve_and_reveal_ritual(view, character)

    assert has_element?(
             view,
             "#spell-compose-error",
             "Связь Башни с дальним толкователем оборвалась прежде, чем он прочёл формулу. Попробуйте повторить ритуал."
           )

    assert_push_event(view, "spell_result", %{ok: false})
  end

  test "a DeepSeek outage is shown without exposing the provider response", %{
    conn: conn,
    character: character,
    the_tower: the_tower
  } do
    configure_spell_provider(
      {:error,
       {:deepseek_api, 503,
        %{"error" => %{"message" => "internal gateway topology must remain secret"}}}}
    )

    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")

    render_hook(view, "spell_compile", %{
      "school" => "fire",
      "actio" => "Ictus",
      "tempus" => "Momentum"
    })

    assert %{status: :revealed, outcome: %{"kind" => "failure"}} =
             resolve_and_reveal_ritual(view, character)

    assert has_element?(
             view,
             "#spell-compose-error",
             "Дальний толкователь сейчас молчит. Формула здесь ни при чём; повторите ритуал, когда связь с Башней укрепится."
           )

    assert_push_event(view, "spell_result", %{ok: false})
  end

  test "the player explicitly inscribes a selected spell and activates that grimoire", %{
    conn: conn,
    character: character,
    the_tower: the_tower,
    base_spell: base_spell,
    grimoire: grimoire
  } do
    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook/books")

    assert has_element?(view, "#grimoire-#{grimoire.id}")

    # One tap on the formula writes it: no select, no second step.
    view
    |> element("#grimoire-inscribe-#{grimoire.id}-#{base_spell.id}")
    |> render_click()

    assert Grimoires.spell_inscribed?(grimoire.id, base_spell.id)

    view
    |> element("#grimoire-activate-#{grimoire.id}")
    |> render_click()

    assert %{id: active_id} = Grimoires.active_grimoire_for_character(character.id)
    assert active_id == grimoire.id
  end

  # Creating a formula and arranging a loadout are different errands, so a link
  # that means one of them must not land on the other.
  test "each leaf of the book is its own destination", %{
    conn: conn,
    character: character,
    the_tower: the_tower
  } do
    character = move_to(character, the_tower)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook/books")
    assert has_element?(view, "#grimoire-loadouts")
    assert has_element?(view, "#spellbook-tab-grimoires[aria-current='page']")

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook/library")
    assert has_element?(view, "#spell-library")
    assert has_element?(view, "#spellbook-tab-spells[aria-current='page']")

    # The bare path still opens on the circle, as it always did.
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook")
    assert has_element?(view, "#spellbook-tab-cast[aria-current='page']")
  end

  test "the player renames and burns a spell from the library", %{
    conn: conn,
    character: character,
    the_tower: the_tower,
    base_spell: base_spell,
    grimoire: grimoire
  } do
    character = move_to(character, the_tower)
    {:ok, _entry} = Play.inscribe_spell(character, grimoire.id, base_spell.id)
    assert Grimoires.spell_inscribed?(grimoire.id, base_spell.id)

    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook/library")

    view
    |> form("#spell-rename-form-#{base_spell.id}", %{
      "spell_id" => base_spell.id,
      "name" => "Первое пламя"
    })
    |> render_submit()

    assert %{name: "Первое пламя"} = Repo.get!(Spells.Spell, base_spell.id)

    # The formula itself is untouched by a rename.
    assert %{formula: "Ignis Prima"} = Repo.get!(Spells.Spell, base_spell.id)

    view
    |> element("#spell-delete-#{base_spell.id}")
    |> render_click()

    assert Repo.get(Spells.Spell, base_spell.id) == nil

    # Burning the formula tears it out of every book that held it.
    refute Grimoires.spell_inscribed?(grimoire.id, base_spell.id)
  end

  test "a spell outside its owner's library cannot be burned", %{
    conn: conn,
    realm: realm,
    the_tower: the_tower,
    base_spell: base_spell
  } do
    stranger = character_fixture(realm, the_tower, "stranger", "Stranger")

    assert {:error, :spell_not_found} = Play.delete_spell(stranger, base_spell.id)
    assert {:error, :spell_not_found} = Play.rename_spell(stranger, base_spell.id, "Чужое")
    assert Repo.get(Spells.Spell, base_spell.id)

    {:ok, view, _html} = live(session_conn(conn, stranger), ~p"/spellbook/library")
    refute has_element?(view, "#spell-delete-#{base_spell.id}")
  end

  test "the player renames a grimoire from its shelf entry", %{
    conn: conn,
    character: character,
    the_tower: the_tower,
    grimoire: grimoire
  } do
    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook/books")

    view
    |> form("#grimoire-rename-form-#{grimoire.id}", %{
      "grimoire_id" => grimoire.id,
      "name" => "Книга штормов"
    })
    |> render_submit()

    assert %{name: "Книга штормов"} = MMGO.Repo.get!(MMGO.Grimoires.Grimoire, grimoire.id)
  end

  test "a blank grimoire name is refused and the old one stands", %{
    conn: conn,
    character: character,
    the_tower: the_tower,
    grimoire: grimoire
  } do
    character = move_to(character, the_tower)
    {:ok, view, _html} = live(session_conn(conn, character), ~p"/spellbook/books")

    html =
      view
      |> form("#grimoire-rename-form-#{grimoire.id}", %{
        "grimoire_id" => grimoire.id,
        "name" => "   "
      })
      |> render_submit()

    assert html =~ "Имя переплёта"
    assert %{name: "Дорожный гримуар"} = MMGO.Repo.get!(MMGO.Grimoires.Grimoire, grimoire.id)
  end

  defp session_conn(conn, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, character.account_id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
  end

  defp arena_session_conn(conn, account, character) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:current_account_id, account.id)
    |> Plug.Conn.put_session(:current_character_id, character.id)
    |> Plug.Conn.put_session(:game_mode, "arena")
  end

  defp resolve_and_reveal_ritual(view, character) do
    attempt = Creation.active_attempt(character.id)
    assert attempt

    assert :ok =
             ResolveCreationAttemptWorker.perform(%Oban.Job{
               args: %{"attempt_id" => attempt.id}
             })

    resolved_attempt = Creation.get_attempt(attempt.id)
    assert resolved_attempt.status in [:sealed_success, :sealed_failure, :revealed]

    if resolved_attempt.status != :revealed do
      assert {:ok, _revealed_attempt} =
               Creation.reveal(attempt.id, now: resolved_attempt.completes_at)
    end

    _ = render(view)
    Creation.get_attempt(attempt.id)
  end

  defp configure_spell_provider(result) do
    ai_config = Application.fetch_env!(:mmgo, MMGO.AI)
    previous_provider_result = Application.get_env(:mmgo, MMGO.TestSpellbookAIProvider)

    Application.put_env(
      :mmgo,
      MMGO.AI,
      Keyword.put(ai_config, :default_provider, MMGO.TestSpellbookAIProvider)
    )

    Application.put_env(:mmgo, MMGO.TestSpellbookAIProvider, result)

    on_exit(fn ->
      Application.put_env(:mmgo, MMGO.AI, ai_config)

      if is_nil(previous_provider_result) do
        Application.delete_env(:mmgo, MMGO.TestSpellbookAIProvider)
      else
        Application.put_env(:mmgo, MMGO.TestSpellbookAIProvider, previous_provider_result)
      end
    end)
  end

  defp move_to(character, location) do
    character
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end

  defp create_active_base(character, location) do
    %Base{}
    |> Base.changeset(%{
      name: "#{location.name} Tower Room",
      kind: :city_purchase,
      status: :active,
      storage_weight_capacity: 250,
      owner_character_id: character.id,
      realm_id: character.realm_id,
      location_id: location.id,
      built_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp create_active_journey(character, realm, route, from_location, to_location) do
    started_at = DateTime.utc_now()

    %Journey{}
    |> Journey.changeset(%{
      character_id: character.id,
      realm_id: realm.id,
      route_id: route.id,
      from_location_id: from_location.id,
      to_location_id: to_location.id,
      status: :active,
      travel_days: 2,
      food_units_consumed: 0,
      encumbrance_penalty_days: 0,
      carried_weight: 0,
      carry_capacity: 100,
      started_at: started_at,
      arrival_at: DateTime.add(started_at, 86_400, :second),
      metadata: %{}
    })
    |> Repo.insert!()
  end

  defp spell_fixture(character, name, formula, school) do
    {:ok, spell} =
      Spells.create_spell(character, %{
        name: name,
        formula: formula,
        school: school,
        description: "A stable spell for the spellbook fixture.",
        targeting: :enemy,
        delivery_form: :sphere,
        effects: [
          %{applies_to: :target, state: "impact", intensity: 10, variance: 1, duration: 0}
        ],
        failure_profile: %{difficulty: 10, base_success_rate: 85, partial_success_rate: 10}
      })

    spell
  end

  defp character_fixture(realm, location, handle, name) do
    account =
      %Account{}
      |> Account.registration_changeset(%{display_name: name, handle: handle})
      |> Repo.insert!()

    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: :active, level: 10, xp: 0})
    |> Repo.insert!()
    |> Character.travel_changeset(%{current_location_id: location.id})
    |> Repo.update!()
  end
end
