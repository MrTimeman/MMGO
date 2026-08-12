defmodule MMGO.Accounts.SpecialProfiles do
  @moduledoc """
  Idempotent provisioning for the closed-alpha sealed-spirit account.

  The exceptional movement and presence policy lives on Albert's character
  metadata. Tamiorn remains an ordinary character despite sharing the account.
  """

  import Ecto.Query, warn: false

  alias MMGO.Accounts.{Account, Character, TelegramIdentity}
  alias MMGO.Academy.{Enrollment, Specialization}
  alias MMGO.Alchemy.Recipe, as: AlchemyRecipe
  alias MMGO.Alchemy.Workshop, as: AlchemyWorkshop
  alias MMGO.Bases.Base
  alias MMGO.Crafting.Recipe, as: CraftingRecipe
  alias MMGO.Crafting.Workshop, as: CraftingWorkshop
  alias MMGO.Federation.Migration
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.SecretCult
  alias MMGO.Travel.Journey
  alias MMGO.Worlds.{Location, Realm}

  @albert_name "Альберт Латыпов"
  @tamiorn_name "Тамиорн Найло"
  @schools ~w(fire water earth air life death chaos order)
  @tracks ~w(wizardry alchemy mastery)
  @mechanics ~w(spellcraft alchemy crafting academia dungeons organizations economy)
  @alchemy_recipes ~w(
    academy_alchemy_refined_mending_tonic
    academy_alchemy_refined_ward_phial
    academy_alchemy_refined_dazing_flask
  )
  @ordinary_max_base_capacity 350
  @standard_alchemy_tools ~w(cauldron retort alembic)
  @standard_crafting_tools ~w(forge anvil workbench)
  @ordinary_safe_metadata_keys ~w(
    source
    survival_state
    xp_source_repetition
    migrated_from_realm_id
    imported_from_realm_slug
  )

  def configured_telegram_user_id do
    Application.get_env(:mmgo, __MODULE__, [])[:telegram_user_id]
  end

  def special_telegram_user_id?(telegram_user_id) when is_integer(telegram_user_id),
    do: telegram_user_id == configured_telegram_user_id()

  def special_telegram_user_id?(_telegram_user_id), do: false

  @doc "Restricts a configured operator handle to Albert on the special multi-profile account."
  def operator_profile_allowed?(%Character{} = character) do
    case Repo.get_by(TelegramIdentity, account_id: character.account_id) do
      %TelegramIdentity{telegram_user_id: telegram_user_id} ->
        not special_telegram_user_id?(telegram_user_id) or canonical_albert_profile?(character)

      nil ->
        true
    end
  end

  def operator_profile_allowed?(_character), do: false

  def reconcile(%Account{} = account, %Realm{} = realm) do
    Repo.transaction(fn ->
      characters =
        Character
        |> where([character], character.account_id == ^account.id)
        |> order_by([character], asc: character.inserted_at, asc: character.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      realm_characters =
        Enum.filter(characters, &(&1.realm_id == realm.id and non_arena_profile?(&1)))

      albert = Enum.find(realm_characters, &albert_name?/1)
      tamiorn = Enum.find(realm_characters, &(&1.name == @tamiorn_name))
      legacy = legacy_character(realm_characters, tamiorn)

      previous_playable_id =
        characters
        |> Enum.find(&(ordinary_world_profile?(&1) and &1.status in [:active, :new]))
        |> then(&(&1 && &1.id))

      active_migration = active_migration_for_account(account.id)

      initial_provision? = is_nil(albert) or is_nil(tamiorn)

      if initial_provision? do
        freeze_playable_profiles_except!(characters, migration_playable_ids(active_migration))
      end

      tower = Repo.get_by(Location, realm_id: realm.id, slug: "the-tower")

      albert =
        ensure_albert!(
          albert || legacy,
          account,
          realm,
          tower,
          is_nil(albert) and not is_nil(legacy)
        )

      albert = ensure_secret_passage_access!(albert)
      ensure_academy_records!(albert)
      ensure_tower_fortress!(albert, tower)
      new_profile_status = if(is_nil(active_migration), do: :new, else: :frozen)
      tamiorn = ensure_tamiorn!(tamiorn, account, realm, new_profile_status)

      characters =
        Character
        |> where([character], character.account_id == ^account.id)
        |> order_by([character], asc: character.inserted_at, asc: character.id)
        |> preload([:realm, :current_location])
        |> Repo.all()

      characters = preserve_migration_profiles!(characters, active_migration)

      if is_nil(active_migration) do
        _selected_profile =
          ensure_playable_profile!(characters, previous_playable_id, tamiorn.id, albert.id)
      end

      characters =
        Character
        |> where([character], character.account_id == ^account.id)
        |> order_by([character], asc: character.inserted_at, asc: character.id)
        |> preload([:realm, :current_location])
        |> Repo.all()

      selected =
        Enum.find(characters, &(ordinary_world_profile?(&1) and &1.status == :active)) ||
          Enum.find(characters, &(&1.id == tamiorn.id and &1.status == :new)) ||
          Enum.find(characters, &(&1.id == tamiorn.id)) ||
          Enum.find(characters, &(&1.id == albert.id))

      %{albert: albert, tamiorn: tamiorn, character: selected, characters: characters}
    end)
  end

  defp ensure_albert!(nil, account, realm, tower, _force_tower?) do
    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(albert_attrs(%{}, :frozen, tower))
    |> Repo.insert!()
    |> place_at_tower(tower)
  end

  defp ensure_albert!(%Character{} = character, _account, _realm, tower, force_tower?) do
    character = Repo.get!(Character, character.id)

    updated_character =
      character
      |> Character.changeset(
        albert_attrs(character.metadata || %{}, character.status, tower)
        |> Map.put(:name, @albert_name)
      )
      |> Repo.update!()

    if force_tower? or is_nil(updated_character.current_location_id) do
      place_at_tower(updated_character, tower)
    else
      updated_character
    end
  end

  defp ensure_tamiorn!(nil, account, realm, new_profile_status) do
    %Character{account_id: account.id, realm_id: realm.id}
    |> Character.changeset(%{
      name: @tamiorn_name,
      status: new_profile_status,
      metadata: %{"profile_kind" => "ordinary"}
    })
    |> Repo.insert!()
  end

  defp ensure_tamiorn!(%Character{} = character, _account, _realm, _new_profile_status) do
    metadata = ordinary_tamiorn_metadata(character.metadata)

    character
    |> Character.changeset(%{name: @tamiorn_name, metadata: metadata})
    |> Repo.update!()
  end

  defp albert_attrs(metadata, status, tower) do
    legendary_metadata = %{
      "profile_kind" => "sealed_spirit",
      "hidden_presence" => true,
      "progression_tier" => "legendary",
      "completed_education" => ~w(basic_education academy_core extended_study academia),
      "mastered_tracks" => @tracks,
      "unlocked_mechanics" => @mechanics,
      "unlocked_schools" => @schools,
      "valedictorian_bonus_schools" => @schools,
      "academy_recipe_unlocks" => @alchemy_recipes
    }

    legendary_metadata =
      if tower do
        Map.put(legendary_metadata, "sealed_anchor_location_id", tower.id)
      else
        legendary_metadata
      end

    %{
      name: @albert_name,
      status: status,
      level: 100,
      xp: Progression.xp_for_level(100),
      metadata: Map.merge(metadata, legendary_metadata)
    }
  end

  defp place_at_tower(character, %Location{} = tower) do
    now = DateTime.utc_now()

    from(journey in Journey,
      where: journey.character_id == ^character.id and journey.status == :active
    )
    |> Repo.update_all(set: [status: :cancelled, completed_at: now, updated_at: now])

    character
    |> Character.travel_changeset(%{current_location_id: tower.id})
    |> Repo.update!()
  end

  defp place_at_tower(character, nil), do: character

  defp legacy_character(realm_characters, tamiorn) do
    Enum.find(realm_characters, fn character -> is_nil(tamiorn) or character.id != tamiorn.id end)
  end

  defp ensure_playable_profile!(characters, previous_playable_id, tamiorn_id, albert_id) do
    playable =
      Enum.find(characters, &(ordinary_world_profile?(&1) and &1.status in [:active, :new]))

    target =
      Enum.find(characters, &(&1.id == previous_playable_id)) ||
        Enum.find(characters, &(&1.id == tamiorn_id)) ||
        Enum.find(characters, &(&1.id == albert_id))

    playable || activate_profile!(target)
  end

  defp activate_profile!(%Character{} = character) do
    status = if(is_binary(character.current_location_id), do: :active, else: :new)

    character
    |> Character.changeset(%{status: status})
    |> Repo.update!()
  end

  defp activate_profile!(nil), do: Repo.rollback(:special_profiles_unavailable)

  defp active_migration_for_account(account_id) do
    Repo.one(
      from migration in Migration,
        where: migration.account_id == ^account_id and migration.status == :active,
        order_by: [asc: migration.inserted_at, asc: migration.id],
        limit: 1
    )
  end

  defp preserve_migration_profiles!(characters, nil), do: characters

  defp preserve_migration_profiles!(
         characters,
         %Migration{mode: :local, destination_character_id: destination_character_id}
       )
       when is_binary(destination_character_id) do
    freeze_playable_profiles_except!(characters, MapSet.new([destination_character_id]))
  end

  defp preserve_migration_profiles!(characters, %Migration{}) do
    freeze_playable_profiles_except!(characters, MapSet.new())
  end

  defp migration_playable_ids(%Migration{
         mode: :local,
         destination_character_id: destination_character_id
       })
       when is_binary(destination_character_id),
       do: MapSet.new([destination_character_id])

  defp migration_playable_ids(_migration), do: MapSet.new()

  defp freeze_playable_profiles_except!(characters, allowed_ids) do
    Enum.map(characters, fn
      %Character{status: status} = character when status in [:active, :new] ->
        if not ordinary_world_profile?(character) or MapSet.member?(allowed_ids, character.id) do
          character
        else
          character
          |> Character.changeset(%{status: :frozen})
          |> Repo.update!()
        end

      character ->
        character
    end)
  end

  defp ensure_secret_passage_access!(%Character{} = character) do
    case SecretCult.ensure_maximum_passage_access(character) do
      {:ok, %{character: updated_character}} -> updated_character
      {:error, :secret_cult_unavailable} -> character
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_academy_records!(%Character{} = character) do
    now = DateTime.utc_now()
    started_at = DateTime.add(now, -86_400, :second)

    programs = [
      {:basic_education, nil, %{}},
      {:academy_core, :wizardry, %{"primary_school" => "fire", "secondary_school" => "air"}},
      {:academy_core, :alchemy, %{}},
      {:academy_core, :mastery, %{}},
      {:extended_study, nil, %{}},
      {:academia, nil, %{}}
    ]

    Enum.each(programs, fn {program_type, track, metadata} ->
      enrollment_query =
        from enrollment in Enrollment,
          where:
            enrollment.character_id == ^character.id and
              enrollment.program_type == ^program_type and enrollment.status == :completed

      enrollment_query =
        if is_nil(track) do
          from enrollment in enrollment_query, where: is_nil(enrollment.track)
        else
          from enrollment in enrollment_query, where: enrollment.track == ^track
        end

      unless Repo.exists?(enrollment_query) do
        %Enrollment{}
        |> Enrollment.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          program_type: program_type,
          track: track,
          status: :completed,
          funding_type: :grant,
          started_at: started_at,
          expected_completion_at: now,
          completed_at: now,
          metadata:
            Map.merge(metadata, %{
              "outcome_tier" => "distinction",
              "progression_source" => "closed_alpha_maximum"
            })
        })
        |> Repo.insert!()
      end
    end)

    active_specialization =
      Repo.get_by(Specialization, character_id: character.id, status: :active)

    active_wizardry =
      case active_specialization do
        %Specialization{track: :wizardry} = specialization ->
          specialization

        %Specialization{} = specialization ->
          specialization
          |> Specialization.changeset(%{status: :retired, ended_at: now})
          |> Repo.update!()

          nil

        nil ->
          nil
      end

    if is_nil(active_wizardry) do
      %Specialization{}
      |> Specialization.changeset(%{
        character_id: character.id,
        realm_id: character.realm_id,
        track: :wizardry,
        status: :active,
        primary_school: :fire,
        secondary_school: :air,
        started_at: started_at,
        metadata: %{"progression_source" => "closed_alpha_maximum"}
      })
      |> Repo.insert!()
    end

    Enum.each([:alchemy, :mastery], fn track ->
      unless Repo.exists?(
               from specialization in Specialization,
                 where:
                   specialization.character_id == ^character.id and
                     specialization.track == ^track
             ) do
        %Specialization{}
        |> Specialization.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          track: track,
          status: :retired,
          started_at: started_at,
          ended_at: now,
          metadata: %{"progression_source" => "closed_alpha_maximum"}
        })
        |> Repo.insert!()
      end
    end)
  end

  defp ensure_tower_fortress!(%Character{} = character, %Location{} = tower) do
    now = DateTime.utc_now()

    base =
      Base
      |> where(
        [base],
        base.owner_character_id == ^character.id and base.location_id == ^tower.id
      )
      |> order_by(
        [base],
        asc: fragment("CASE WHEN ? = 'active' THEN 0 ELSE 1 END", base.status),
        asc: base.inserted_at,
        asc: base.id
      )
      |> limit(1)
      |> Repo.one()
      |> Kernel.||(%Base{
        owner_character_id: character.id,
        realm_id: character.realm_id,
        location_id: tower.id
      })

    base
    |> Base.changeset(%{
      name: "Башня Альберта Латыпова",
      kind: :custom_build,
      status: :active,
      storage_weight_capacity:
        max(base.storage_weight_capacity || 0, @ordinary_max_base_capacity),
      built_at: base.built_at || now,
      metadata:
        Map.merge(base.metadata || %{}, %{
          "fortress" => %{"tier" => 5, "ward_intensity" => 100},
          "progression_source" => "closed_alpha_maximum"
        })
    })
    |> Repo.insert_or_update!()

    alchemy_tools =
      AlchemyRecipe
      |> Repo.all()
      |> Enum.flat_map(&List.wrap(&1.required_tool_codes))
      |> Kernel.++(@standard_alchemy_tools)
      |> Enum.uniq()

    crafting_tools =
      CraftingRecipe
      |> Repo.all()
      |> Enum.flat_map(&List.wrap(&1.required_tool_codes))
      |> Kernel.++(@standard_crafting_tools)
      |> Enum.uniq()

    ensure_workshop!(
      AlchemyWorkshop,
      character,
      tower,
      "Алхимическая лаборатория Башни",
      alchemy_tools
    )

    ensure_workshop!(
      CraftingWorkshop,
      character,
      tower,
      "Кузница Башни",
      crafting_tools
    )
  end

  defp ensure_tower_fortress!(_character, nil), do: :ok

  defp ensure_workshop!(schema, character, tower, name, required_tools) do
    workshop =
      schema
      |> where([workshop], workshop.owner_character_id == ^character.id)
      |> order_by(
        [workshop],
        asc: fragment("CASE WHEN ? = 'active' THEN 0 ELSE 1 END", workshop.status),
        asc: workshop.inserted_at,
        asc: workshop.id
      )
      |> limit(1)
      |> Repo.one()
      |> Kernel.||(
        struct(schema,
          owner_character_id: character.id,
          realm_id: character.realm_id,
          location_id: tower.id
        )
      )

    installed_tools = Enum.uniq((workshop.installed_tool_codes || []) ++ required_tools)

    workshop
    |> schema.changeset(%{
      name: name,
      status: :active,
      owner_character_id: character.id,
      realm_id: character.realm_id,
      location_id: tower.id,
      installed_tool_codes: installed_tools,
      metadata:
        Map.merge(workshop.metadata || %{}, %{
          "facility_tier" => "max_ordinary",
          "progression_source" => "closed_alpha_maximum"
        })
    })
    |> Repo.insert_or_update!()
  end

  defp ordinary_tamiorn_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.take(@ordinary_safe_metadata_keys)
    |> Map.put("profile_kind", "ordinary")
  end

  defp ordinary_tamiorn_metadata(_metadata), do: %{"profile_kind" => "ordinary"}

  defp albert_name?(%Character{name: @albert_name}), do: true
  defp albert_name?(_character), do: false

  defp canonical_albert_profile?(%Character{} = character) do
    Repo.exists?(
      from candidate in Character,
        join: realm in Realm,
        on: realm.id == candidate.realm_id,
        where:
          candidate.id == ^character.id and candidate.account_id == ^character.account_id and
            candidate.name == ^@albert_name and realm.is_default == true
    )
  end

  defp non_arena_profile?(%Character{metadata: metadata}) when is_map(metadata),
    do: Map.get(metadata, "profile_kind") != "arena"

  defp non_arena_profile?(_character), do: true

  defp ordinary_world_profile?(%Character{metadata: metadata}) when is_map(metadata),
    do: Map.get(metadata, "profile_kind") not in ["arena", "sealed_spirit"]

  defp ordinary_world_profile?(_character), do: true
end
