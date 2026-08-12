defmodule MMGO.AccountsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Accounts
  alias MMGO.Accounts.{Account, Character, CharacterProfiles, SpecialProfiles, TelegramIdentity}
  alias MMGO.Academy
  alias MMGO.Academy.{Enrollment, Specialization}
  alias MMGO.Alchemy.Workshop, as: AlchemyWorkshop
  alias MMGO.Bases.Base
  alias MMGO.Crafting.Workshop, as: CraftingWorkshop
  alias MMGO.Federation.{Migration, RemoteRealm}
  alias MMGO.Repo
  alias MMGO.Travel.{Journey}
  alias MMGO.Worlds

  setup do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true
      })

    {:ok, tower} =
      Worlds.create_location(realm, %{
        slug: "the-tower",
        name: "The Tower",
        kind: :tower,
        x: 10,
        y: 10,
        safe_zone: false
      })

    %{realm: realm, tower: tower}
  end

  test "provision_from_telegram/1 creates account, identity, and starter character", %{
    realm: realm
  } do
    telegram_user = %{
      "id" => 1001,
      "username" => "arcanist",
      "first_name" => "Arc",
      "last_name" => "Anist",
      "language_code" => "en",
      "photo_url" => "https://t.me/i/userpic/320/arcanist.jpg"
    }

    assert {:ok, %{account: account, telegram_identity: identity, character: character}} =
             Accounts.provision_from_telegram(telegram_user)

    assert account.display_name == "Arc Anist"
    assert account.handle =~ ~r/^arcanist-/

    assert account.settings["telegram_photo_url"] ==
             "https://t.me/i/userpic/320/arcanist.jpg"

    assert identity.telegram_user_id == 1001
    assert character.realm_id == realm.id
    assert character.level == 1
    assert is_nil(account.default_character_id)
    assert is_nil(Accounts.get_default_world_character_for_account(account.id))
    assert Repo.aggregate(Account, :count, :id) == 1
    assert Repo.aggregate(TelegramIdentity, :count, :id) == 1
    assert Repo.aggregate(Character, :count, :id) == 1
  end

  test "provision_from_telegram/1 updates an existing identity without duplicating records" do
    assert {:ok, %{account: account}} =
             Accounts.provision_from_telegram(%{
               "id" => 2002,
               "username" => "embermage",
               "first_name" => "Ember"
             })

    assert {:ok, %{account: same_account, telegram_identity: identity}} =
             Accounts.provision_from_telegram(%{
               "id" => 2002,
               "username" => "emberqueen",
               "first_name" => "Ember",
               "last_name" => "Queen",
               "photo_url" => "https://t.me/i/userpic/320/emberqueen.jpg"
             })

    assert same_account.id == account.id
    assert same_account.display_name == "Ember Queen"
    assert same_account.settings["telegram_username"] == "emberqueen"

    assert same_account.settings["telegram_photo_url"] ==
             "https://t.me/i/userpic/320/emberqueen.jpg"

    assert identity.telegram_username == "emberqueen"
    assert Repo.aggregate(Account, :count, :id) == 1
    assert Repo.aggregate(TelegramIdentity, :count, :id) == 1
    assert Repo.aggregate(Character, :count, :id) == 1
  end

  test "provision_from_telegram/1 rejects invalid payloads" do
    assert {:error, :invalid_update} = Accounts.provision_from_telegram(%{"username" => "no-id"})
  end

  test "special Telegram identity idempotently receives sealed Albert and ordinary Tamiorn", %{
    tower: tower
  } do
    telegram_user = %{
      "id" => 1_265_881_543,
      "username" => "albert",
      "first_name" => "Albert"
    }

    assert {:ok, %{account: account, character: selected}} =
             Accounts.provision_from_telegram(telegram_user)

    assert selected.name == "Тамиорн Найло"
    assert selected.status == :new
    assert is_nil(Accounts.get_default_world_character_for_account(account.id))

    characters = Accounts.list_characters_for_account(account.id)
    assert Enum.map(characters, & &1.name) |> Enum.sort() == ["Альберт Латыпов", "Тамиорн Найло"]

    albert = Enum.find(characters, &(&1.name == "Альберт Латыпов"))
    tamiorn = Enum.find(characters, &(&1.name == "Тамиорн Найло"))

    assert albert.status == :frozen
    assert albert.level == 100
    assert albert.xp == 1_000_000
    assert albert.current_location_id == tower.id
    assert albert.metadata["profile_kind"] == "sealed_spirit"
    assert albert.metadata["hidden_presence"] == true
    assert albert.metadata["sealed_anchor_location_id"] == tower.id
    assert albert.metadata["progression_tier"] == "legendary"
    refute Map.has_key?(albert.metadata, "admin_access")
    assert tamiorn.metadata["profile_kind"] == "ordinary"

    assert %Base{} =
             fortress =
             Repo.get_by(Base, owner_character_id: albert.id, location_id: tower.id)

    assert fortress.status == :active
    assert fortress.kind == :custom_build
    assert fortress.storage_weight_capacity == 350
    assert fortress.metadata["fortress"] == %{"tier" => 5, "ward_intensity" => 100}

    assert %AlchemyWorkshop{} =
             alchemy_workshop =
             Repo.get_by(AlchemyWorkshop, owner_character_id: albert.id, status: :active)

    assert alchemy_workshop.location_id == tower.id
    assert Enum.all?(~w(cauldron retort alembic), &(&1 in alchemy_workshop.installed_tool_codes))

    assert %CraftingWorkshop{} =
             crafting_workshop =
             Repo.get_by(CraftingWorkshop, owner_character_id: albert.id, status: :active)

    assert crafting_workshop.location_id == tower.id
    assert Enum.all?(~w(forge anvil workbench), &(&1 in crafting_workshop.installed_tool_codes))
    refute Repo.get_by(Base, owner_character_id: tamiorn.id)
    refute Repo.get_by(AlchemyWorkshop, owner_character_id: tamiorn.id)
    refute Repo.get_by(CraftingWorkshop, owner_character_id: tamiorn.id)
    assert Academy.program_completed?(albert.id, :basic_education)
    assert Academy.program_completed?(albert.id, :academy_core)
    assert Academy.program_completed?(albert.id, :extended_study)
    assert Academy.program_completed?(albert.id, :academia)
    assert Repo.aggregate(from(e in Enrollment, where: e.character_id == ^albert.id), :count) == 6

    assert Enum.sort(Enum.map(Academy.list_specializations(albert.id), & &1.track)) ==
             [:alchemy, :mastery, :wizardry]

    assert %Specialization{track: :wizardry, status: :active} =
             Academy.active_specialization(albert.id)

    historic_basic =
      Repo.one!(
        from enrollment in Enrollment,
          where:
            enrollment.character_id == ^albert.id and
              enrollment.program_type == :basic_education,
          limit: 1
      )

    %Enrollment{}
    |> Enrollment.changeset(%{
      character_id: albert.id,
      realm_id: albert.realm_id,
      program_type: :basic_education,
      status: :completed,
      funding_type: :grant,
      started_at: DateTime.add(historic_basic.started_at, -86_400, :second),
      expected_completion_at: historic_basic.started_at,
      completed_at: historic_basic.started_at,
      metadata: %{"outcome_tier" => "pass"}
    })
    |> Repo.insert!()

    fortress
    |> Base.changeset(%{status: :abandoned})
    |> Repo.update!()

    %Base{
      owner_character_id: albert.id,
      realm_id: albert.realm_id,
      location_id: tower.id
    }
    |> Base.changeset(%{
      name: "Старая башенная запись",
      kind: :custom_build,
      status: :abandoned,
      storage_weight_capacity: 10,
      built_at: DateTime.utc_now()
    })
    |> Repo.insert!()

    alchemy_workshop
    |> AlchemyWorkshop.changeset(%{status: :inactive})
    |> Repo.update!()

    %AlchemyWorkshop{}
    |> AlchemyWorkshop.changeset(%{
      owner_character_id: albert.id,
      realm_id: albert.realm_id,
      location_id: tower.id,
      name: "Старая лаборатория",
      status: :inactive,
      installed_tool_codes: []
    })
    |> Repo.insert!()

    crafting_workshop
    |> CraftingWorkshop.changeset(%{status: :inactive})
    |> Repo.update!()

    %CraftingWorkshop{}
    |> CraftingWorkshop.changeset(%{
      owner_character_id: albert.id,
      realm_id: albert.realm_id,
      location_id: tower.id,
      name: "Старая кузница",
      status: :inactive,
      installed_tool_codes: []
    })
    |> Repo.insert!()

    assert {:ok, %{account: same_account}} = Accounts.provision_from_telegram(telegram_user)
    assert same_account.id == account.id
    assert length(Accounts.list_characters_for_account(account.id)) == 2

    assert Repo.aggregate(
             from(base in Base,
               where: base.owner_character_id == ^albert.id and base.status == :active
             ),
             :count
           ) == 1

    assert Repo.aggregate(
             from(workshop in AlchemyWorkshop,
               where: workshop.owner_character_id == ^albert.id and workshop.status == :active
             ),
             :count
           ) == 1

    assert Repo.aggregate(
             from(workshop in CraftingWorkshop,
               where: workshop.owner_character_id == ^albert.id and workshop.status == :active
             ),
             :count
           ) == 1
  end

  test "reconcile authoritatively strips special powers from a contaminated Tamiorn", %{
    realm: realm,
    tower: tower
  } do
    assert {:ok, %{account: account}} =
             Accounts.provision_from_telegram(%{
               "id" => 1_265_881_543,
               "username" => "contaminated-tamiorn",
               "first_name" => "Albert"
             })

    characters = Accounts.list_characters_for_account(account.id)
    original_albert = Enum.find(characters, &(&1.name == "Альберт Латыпов"))
    tamiorn = Enum.find(characters, &(&1.name == "Тамиорн Найло"))

    safe_metadata = %{
      "source" => "telegram_mini_app",
      "survival_state" => %{"starvation_days" => 2},
      "xp_source_repetition" => %{"travel" => %{"count" => 1}},
      "migrated_from_realm_id" => Ecto.UUID.generate(),
      "imported_from_realm_slug" => "old-realm"
    }

    contaminated_metadata =
      Map.merge(safe_metadata, %{
        "profile_kind" => "sealed_spirit",
        "hidden_presence" => true,
        "sealed_anchor_location_id" => tower.id,
        "progression_tier" => "legendary",
        "completed_education" => ~w(basic_education academia),
        "mastered_tracks" => ~w(wizardry alchemy mastery),
        "unlocked_mechanics" => ~w(spellcraft alchemy crafting),
        "unlocked_schools" => ~w(fire water earth air life death chaos order),
        "valedictorian_bonus_schools" => ~w(fire water earth air),
        "academy_recipe_unlocks" => ["academy_alchemy_refined_ward_phial"],
        "admin_access" => true,
        "operator_access" => true,
        "permissions" => ["admin", "teleport"]
      })

    contaminated_tamiorn =
      tamiorn
      |> Character.changeset(%{metadata: contaminated_metadata})
      |> Repo.update!()

    assert SpecialProfiles.operator_profile_allowed?(%{
             original_albert
             | metadata: %{"profile_kind" => "ordinary"}
           })

    refute SpecialProfiles.operator_profile_allowed?(contaminated_tamiorn)

    refute SpecialProfiles.operator_profile_allowed?(%{
             contaminated_tamiorn
             | name: "Альберт Латыпов"
           })

    assert {:ok, profiles} = SpecialProfiles.reconcile(account, realm)
    assert profiles.albert.id == original_albert.id
    assert profiles.tamiorn.id == tamiorn.id
    assert profiles.tamiorn.metadata == Map.put(safe_metadata, "profile_kind", "ordinary")
    refute CharacterProfiles.sealed_spirit?(profiles.tamiorn)
    refute CharacterProfiles.hidden_presence?(profiles.tamiorn)
    refute CharacterProfiles.legendary_progression?(profiles.tamiorn)
    refute SpecialProfiles.operator_profile_allowed?(profiles.tamiorn)
  end

  test "sealed profiles neither freeze nor replace the ordinary world default", %{
    realm: realm,
    tower: tower
  } do
    assert {:ok, %{account: account}} =
             Accounts.provision_from_telegram(%{
               "id" => 1_265_881_543,
               "username" => "albert",
               "first_name" => "Albert"
             })

    [albert, tamiorn] =
      account.id
      |> Accounts.list_characters_for_account()
      |> Enum.sort_by(& &1.name)

    tamiorn = tamiorn |> Character.changeset(%{status: :active}) |> Repo.update!()

    assert Accounts.get_character_by_handle(realm.id, account.handle).id == tamiorn.id
    assert {:ok, selected_tamiorn} = Accounts.switch_character(account.id, tamiorn.id)
    assert selected_tamiorn.id == tamiorn.id
    assert Accounts.get_default_world_character_for_account(account.id).id == tamiorn.id

    assert {:ok, active_albert} = Accounts.switch_character(account.id, albert.id)
    assert active_albert.status == :active
    assert Accounts.get_character!(tamiorn.id).status == :active
    assert Accounts.get_default_world_character_for_account(account.id).id == tamiorn.id

    assert [] == Accounts.list_active_characters_at_location(realm.id, tower.id)
    assert Accounts.get_character_by_handle(realm.id, account.handle).id == tamiorn.id

    assert {:ok, active_tamiorn} = Accounts.switch_character(account.id, tamiorn.id)
    assert active_tamiorn.status == :active
    assert Accounts.get_character!(albert.id).status == :active

    assert {:ok, %{character: refreshed_character}} =
             Accounts.provision_from_telegram(%{
               "id" => 1_265_881_543,
               "username" => "albert",
               "first_name" => "Albert"
             })

    assert refreshed_character.id == tamiorn.id
    assert Accounts.get_default_world_character_for_account(account.id).id == tamiorn.id
  end

  test "refresh keeps the globally playable profile selected ahead of a frozen default-realm profile",
       %{realm: default_realm} do
    telegram_user = %{"id" => 9_001, "username" => "realm-roamer", "first_name" => "Roamer"}

    assert {:ok, %{account: account, character: default_character}} =
             Accounts.provision_from_telegram(telegram_user)

    default_character
    |> Character.changeset(%{status: :frozen})
    |> Repo.update!()

    {:ok, remote_realm} =
      Worlds.create_realm(%{slug: "remote-profile", name: "Remote Profile"})

    remote_character = character_fixture(account, remote_realm, "Remote Roamer", :active)

    assert {:ok, %{character: selected}} = Accounts.provision_from_telegram(telegram_user)
    assert selected.id == remote_character.id
    assert selected.realm_id != default_realm.id
  end

  test "ordinary MMO identity is unique per account and realm while technical profiles coexist",
       %{
         realm: realm
       } do
    account = account_fixture("realm-identity")
    _ordinary = character_fixture(account, realm, "Realm Identity", :active)

    assert {:error, changeset} =
             %Character{account_id: account.id, realm_id: realm.id}
             |> Character.changeset(%{name: "Duplicate Identity", status: :frozen})
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).account_id

    sealed =
      %Character{account_id: account.id, realm_id: realm.id}
      |> Character.changeset(%{
        name: "Sealed Anchor",
        status: :frozen,
        metadata: %{"profile_kind" => "sealed_spirit", "hidden_presence" => true}
      })
      |> Repo.insert!()

    arena =
      %Character{account_id: account.id, realm_id: realm.id}
      |> Character.changeset(%{
        name: "Arena Identity",
        status: :active,
        metadata: %{"profile_kind" => "arena", "hidden_presence" => true}
      })
      |> Repo.insert!()

    assert sealed.realm_id == realm.id
    assert arena.realm_id == realm.id
  end

  test "persistent default accepts only owned playable ordinary characters", %{realm: realm} do
    owner = account_fixture("default-owner")
    stranger = account_fixture("default-stranger")
    ordinary = character_fixture(owner, realm, "Default Wanderer", :active)
    foreign = character_fixture(stranger, realm, "Foreign Wanderer", :active)

    sealed =
      %Character{account_id: owner.id, realm_id: realm.id}
      |> Character.changeset(%{
        name: "Default Seal",
        status: :frozen,
        metadata: %{"profile_kind" => "sealed_spirit"}
      })
      |> Repo.insert!()

    arena =
      %Character{account_id: owner.id, realm_id: realm.id}
      |> Character.changeset(%{
        name: "Default Arena",
        status: :active,
        metadata: %{"profile_kind" => "arena"}
      })
      |> Repo.insert!()

    refute Accounts.get_default_world_character_for_account(owner.id)
    assert {:error, :not_found} = Accounts.set_default_world_character(owner.id, foreign.id)

    assert {:error, :not_world_character} =
             Accounts.set_default_world_character(owner.id, sealed.id)

    assert {:error, :not_world_character} =
             Accounts.set_default_world_character(owner.id, arena.id)

    assert {:ok, selected} = Accounts.set_default_world_character(owner.id, ordinary.id)
    assert selected.id == ordinary.id
    assert Accounts.get_default_world_character_for_account(owner).id == ordinary.id

    owner
    |> Ecto.Changeset.change(default_character_id: sealed.id)
    |> Repo.update!()

    refute Accounts.get_default_world_character_for_account(owner.id)

    assert {:ok, selected} = Accounts.set_default_world_character(owner.id, ordinary.id)
    assert selected.id == ordinary.id

    ordinary
    |> Character.changeset(%{status: :retired})
    |> Repo.update!()

    refute Accounts.get_default_world_character_for_account(owner.id)
    assert {:error, :not_playable} = Accounts.set_default_world_character(owner.id, ordinary.id)
  end

  test "switching realms persists the ordinary command default", %{realm: realm} do
    account = account_fixture("default-switch")
    first = character_fixture(account, realm, "First Realm Self", :active)

    {:ok, second_realm} =
      Worlds.create_realm(%{slug: "default-switch-second", name: "Second Default Realm"})

    second = character_fixture(account, second_realm, "Second Realm Self", :frozen)

    assert {:ok, selected_first} = Accounts.switch_character(account.id, first.id)
    assert selected_first.id == first.id
    assert Accounts.get_default_world_character_for_account(account.id).id == first.id

    assert {:ok, selected_second} = Accounts.switch_character(account.id, second.id)
    assert selected_second.id == second.id
    assert Accounts.get_character!(first.id).status == :frozen
    assert Accounts.get_default_world_character_for_account(account.id).id == second.id
  end

  test "reconcile repairs an existing Tamiorn-only account to one playable profile", %{
    realm: realm
  } do
    account = account_fixture("tamiorn-only")
    tamiorn = character_fixture(account, realm, "Тамиорн Найло", :active)

    assert {:ok, profiles} = SpecialProfiles.reconcile(account, realm)
    assert profiles.tamiorn.id == tamiorn.id

    playable = Enum.filter(profiles.characters, &(&1.status in [:active, :new]))
    assert [%Character{id: playable_id}] = playable
    assert playable_id == tamiorn.id
  end

  test "first legacy conversion cancels its journey and anchors Albert only once", %{
    realm: realm,
    tower: tower
  } do
    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "legacy-city",
        name: "Legacy City",
        kind: :city,
        x: 30,
        y: 30,
        safe_zone: true
      })

    {:ok, route} =
      Worlds.create_route(realm, %{
        name: "Legacy Road",
        origin_location_id: city.id,
        destination_location_id: tower.id,
        travel_days: 2,
        risk_level: 5,
        bidirectional: true
      })

    account = account_fixture("legacy-albert")

    legacy =
      account
      |> character_fixture(realm, "Legacy Wizard", :active)
      |> Character.travel_changeset(%{current_location_id: city.id})
      |> Repo.update!()

    now = DateTime.utc_now()

    journey =
      %Journey{}
      |> Journey.changeset(%{
        character_id: legacy.id,
        realm_id: realm.id,
        route_id: route.id,
        from_location_id: city.id,
        to_location_id: tower.id,
        status: :active,
        travel_days: 2,
        food_units_consumed: 0,
        encumbrance_penalty_days: 0,
        carried_weight: 0,
        carry_capacity: 10,
        started_at: now,
        arrival_at: DateTime.add(now, 120, :second)
      })
      |> Repo.insert!()

    assert {:ok, %{albert: albert}} = SpecialProfiles.reconcile(account, realm)
    assert albert.id == legacy.id
    assert albert.current_location_id == tower.id
    assert Repo.get!(Journey, journey.id).status == :cancelled

    albert
    |> Character.travel_changeset(%{current_location_id: city.id})
    |> Repo.update!()

    assert {:ok, %{albert: projected_albert}} = SpecialProfiles.reconcile(account, realm)
    assert projected_albert.current_location_id == city.id
  end

  test "special reprovision preserves the active destination of a local migration", %{
    realm: realm
  } do
    telegram_user = %{
      "id" => 1_265_881_543,
      "username" => "albert-migrating",
      "first_name" => "Albert"
    }

    assert {:ok, %{account: account}} = Accounts.provision_from_telegram(telegram_user)

    tamiorn =
      account.id
      |> Accounts.list_characters_for_account()
      |> Enum.find(&(&1.name == "Тамиорн Найло"))

    {:ok, destination_realm} =
      Worlds.create_realm(%{slug: "migration-destination", name: "Другой мир"})

    destination = character_fixture(account, destination_realm, "Перенесённый образ", :frozen)

    account.id
    |> Accounts.list_characters_for_account()
    |> Enum.each(fn character ->
      character
      |> Character.changeset(%{status: :frozen})
      |> Repo.update!()
    end)

    destination =
      destination
      |> Character.changeset(%{status: :active})
      |> Repo.update!()

    now = DateTime.utc_now()

    %Migration{}
    |> Migration.changeset(%{
      account_id: account.id,
      origin_realm_id: realm.id,
      destination_realm_id: destination_realm.id,
      origin_character_id: tamiorn.id,
      destination_character_id: destination.id,
      destination_character_name: destination.name,
      mode: :local,
      status: :active,
      currency_amount: 1,
      converted_currency_amount: 1,
      source_level: tamiorn.level,
      destination_level: destination.level,
      source_xp: tamiorn.xp,
      destination_xp: destination.xp,
      passive_xp_awarded: 0,
      freeze_started_at: now,
      freeze_ends_at: DateTime.add(now, 86_400, :second)
    })
    |> Repo.insert!()

    assert {:ok, %{character: selected}} = Accounts.provision_from_telegram(telegram_user)
    assert selected.id == destination.id
    assert selected.status == :active

    profiles = Accounts.list_characters_for_account(account.id)
    assert Enum.count(profiles, &(&1.status == :active)) == 1
    assert Accounts.get_character!(destination.id).status == :active
    assert Accounts.get_character!(tamiorn.id).status == :frozen
    assert {:error, :migration_in_progress} = Accounts.switch_character(account.id, tamiorn.id)
  end

  test "initial special reconciliation keeps a migrated destination active and creates Tamiorn frozen",
       %{realm: realm} do
    account = account_fixture("legacy-special-migration")
    legacy = character_fixture(account, realm, "Legacy Albert", :frozen)

    {:ok, destination_realm} =
      Worlds.create_realm(%{slug: "initial-migration-destination", name: "Новый мир"})

    destination = character_fixture(account, destination_realm, "Новый образ", :active)
    now = DateTime.utc_now()

    %Migration{}
    |> Migration.changeset(%{
      account_id: account.id,
      origin_realm_id: realm.id,
      destination_realm_id: destination_realm.id,
      origin_character_id: legacy.id,
      destination_character_id: destination.id,
      destination_character_name: destination.name,
      mode: :local,
      status: :active,
      currency_amount: 1,
      converted_currency_amount: 1,
      source_level: legacy.level,
      destination_level: destination.level,
      source_xp: legacy.xp,
      destination_xp: destination.xp,
      passive_xp_awarded: 0,
      freeze_started_at: now,
      freeze_ends_at: DateTime.add(now, 86_400, :second)
    })
    |> Repo.insert!()

    assert {:ok, profiles} = SpecialProfiles.reconcile(account, realm)
    assert profiles.albert.id == legacy.id
    assert profiles.tamiorn.status == :frozen
    assert Accounts.get_character!(destination.id).status == :active

    assert Enum.count(Accounts.list_characters_for_account(account.id), fn character ->
             character.status == :active
           end) == 1
  end

  test "special reprovision keeps every local profile frozen during a remote migration", %{
    realm: realm
  } do
    telegram_user = %{
      "id" => 1_265_881_543,
      "username" => "albert-remote",
      "first_name" => "Albert"
    }

    assert {:ok, %{account: account}} = Accounts.provision_from_telegram(telegram_user)

    origin =
      account.id
      |> Accounts.list_characters_for_account()
      |> Enum.find(&(&1.name == "Тамиорн Найло"))

    account.id
    |> Accounts.list_characters_for_account()
    |> Enum.each(fn character ->
      character
      |> Character.changeset(%{status: :frozen})
      |> Repo.update!()
    end)

    remote =
      %RemoteRealm{}
      |> RemoteRealm.changeset(%{
        slug: "remote-freeze",
        name: "Дальний мир",
        status: :active,
        manifest_url: "https://remote-freeze.example/manifest",
        public_endpoint: "https://remote-freeze.example",
        currency_code: "REM",
        allow_migration: true,
        population_hint: 10,
        ruleset_version: 1,
        ruleset: %{"magic_scope" => "global"}
      })
      |> Repo.insert!()

    now = DateTime.utc_now()

    %Migration{}
    |> Migration.changeset(%{
      account_id: account.id,
      origin_realm_id: realm.id,
      remote_realm_id: remote.id,
      origin_character_id: origin.id,
      destination_character_name: origin.name,
      mode: :remote,
      status: :active,
      currency_amount: 1,
      converted_currency_amount: 1,
      source_level: origin.level,
      destination_level: origin.level,
      source_xp: origin.xp,
      destination_xp: origin.xp,
      passive_xp_awarded: 0,
      freeze_started_at: now,
      freeze_ends_at: DateTime.add(now, 86_400, :second)
    })
    |> Repo.insert!()

    assert {:ok, %{character: selected}} = Accounts.provision_from_telegram(telegram_user)
    assert selected.status == :frozen
    assert Enum.all?(Accounts.list_characters_for_account(account.id), &(&1.status == :frozen))
    assert {:error, :migration_in_progress} = Accounts.switch_character(account.id, origin.id)
  end

  test "get_active_character_for_account/2 enforces ownership and active statuses", %{
    realm: realm
  } do
    owner = account_fixture("scope-owner")
    stranger = account_fixture("scope-stranger")
    inactive_owner = account_fixture("inactive-owner")
    active_character = character_fixture(owner, realm, "Scope Owner", :active)
    stranger_character = character_fixture(stranger, realm, "Scope Stranger", :active)
    inactive_character = character_fixture(inactive_owner, realm, "Sleeping Owner", :new)

    assert {:ok, scoped_character} =
             Accounts.get_active_character_for_account(owner.id, active_character.id)

    assert scoped_character.account.id == owner.id

    assert {:error, :not_found} =
             Accounts.get_active_character_for_account(owner.id, stranger_character.id)

    assert {:error, :inactive} =
             Accounts.get_active_character_for_account(inactive_owner.id, inactive_character.id)

    suspended_owner =
      owner
      |> Ecto.Changeset.change(status: :suspended)
      |> Repo.update!()

    assert {:error, :inactive} =
             Accounts.get_active_character_for_account(suspended_owner.id, active_character.id)
  end

  defp account_fixture(handle) do
    %Account{}
    |> Account.registration_changeset(%{display_name: handle, handle: handle})
    |> Repo.insert!()
  end

  defp character_fixture(account, realm, name, status) do
    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{name: name, status: status})
    |> Repo.insert!()
  end
end
