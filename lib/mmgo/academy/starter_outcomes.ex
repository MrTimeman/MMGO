defmodule MMGO.Academy.StarterOutcomes do
  @moduledoc """
  Creates the durable, track-specific rewards earned by an Academy Core
  graduate.

  The enrollment metadata is the completion receipt. It lets the browser show
  exactly what the graduate earned and keeps a retried completion from making a
  second copy of the same starter kit.
  """

  import Ecto.Query, warn: false

  alias MMGO.Accounts.Character
  alias MMGO.Academy.{Enrollment, Specialization}
  alias MMGO.Alchemy.Recipe
  alias MMGO.Grimoires.{Grimoire, GrimoireEntry}
  alias MMGO.Inventory
  alias MMGO.Inventory.ItemTemplate
  alias MMGO.Repo
  alias MMGO.Spells

  @recipe_unlocks_key "academy_recipe_unlocks"

  @school_presentations %{
    fire: %{label: "Огонь", formula: "Ignis"},
    water: %{label: "Вода", formula: "Aqua"},
    earth: %{label: "Земля", formula: "Terra"},
    air: %{label: "Воздух", formula: "Aer"},
    life: %{label: "Жизнь", formula: "Vita"},
    death: %{label: "Смерть", formula: "Mors"},
    chaos: %{label: "Хаос", formula: "Chaos"},
    order: %{label: "Порядок", formula: "Ordo"}
  }

  @quality_settings %{
    provisional: %{
      label: "учебное",
      spell_intensity: 6,
      spell_variance: 1,
      spell_success_rate: 78,
      spell_difficulty: 22,
      tool_durability: 12,
      tool_intensity: 7,
      empowerment_multiplier: 2,
      potion_intensity: 5,
      starter_reagents: 3
    },
    standard: %{
      label: "стандартное",
      spell_intensity: 10,
      spell_variance: 2,
      spell_success_rate: 86,
      spell_difficulty: 15,
      tool_durability: 20,
      tool_intensity: 11,
      empowerment_multiplier: 2,
      potion_intensity: 8,
      starter_reagents: 5
    },
    refined: %{
      label: "отличное",
      spell_intensity: 14,
      spell_variance: 3,
      spell_success_rate: 93,
      spell_difficulty: 9,
      tool_durability: 30,
      tool_intensity: 15,
      empowerment_multiplier: 3,
      potion_intensity: 11,
      starter_reagents: 7
    }
  }

  @doc """
  Grants the durable graduation reward bundle inside the caller's transaction.

  This function deliberately uses real spells, grimoires, inventory records,
  recipes, and recipe unlocks. A label on an enrollment alone is not a reward.
  """
  def grant!(
        %Character{} = character,
        %Enrollment{program_type: :academy_core} = enrollment,
        %Specialization{} = specialization,
        outcome_tier
      ) do
    case summary(enrollment) do
      nil ->
        quality = quality_for(enrollment, outcome_tier)

        {updated_character, rewards, extra_metadata} =
          grant_track!(specialization.track, character, enrollment, specialization, quality)

        starter_outcomes =
          %{
            "track" => Atom.to_string(specialization.track),
            "quality" => Atom.to_string(quality),
            "gpa" => MMGO.Academy.gpa_for_enrollment(enrollment.id),
            "rewards" => rewards
          }
          |> Map.merge(extra_metadata)

        updated_enrollment =
          enrollment
          |> Enrollment.changeset(%{
            metadata: Map.put(enrollment.metadata || %{}, "starter_outcomes", starter_outcomes)
          })
          |> Repo.update!()

        %{
          character: updated_character,
          enrollment: updated_enrollment,
          starter_outcomes: starter_outcomes
        }

      starter_outcomes ->
        %{character: character, enrollment: enrollment, starter_outcomes: starter_outcomes}
    end
  end

  def grant!(
        %Character{} = character,
        %Enrollment{program_type: :basic_education} = enrollment,
        _specialization,
        :distinction
      ) do
    case summary(enrollment) do
      nil ->
        settings = quality_settings(:refined)

        spells =
          [
            wizard_spell_attrs(:fire, :bolt, :refined, settings),
            wizard_spell_attrs(:air, :ward, :refined, settings)
          ]
          |> Enum.map(fn attrs ->
            attrs =
              attrs
              |> Map.update!(:tags, &(&1 ++ ["basic_education", "distinction"]))
              |> Map.update!(:narrative_tags, &(&1 ++ ["basic_distinction"]))

            create_starter_spell!(character, attrs)
          end)

        grimoire = academy_grimoire!(character, enrollment, "Почётный гримуар Академии")
        inscribe_starter_spells!(grimoire, spells)

        starter_outcomes = %{
          "track" => "basic_education",
          "quality" => "honors",
          "title" => "Академские почести",
          "gpa" => MMGO.Academy.gpa_for_enrollment(enrollment.id),
          "grimoire_id" => grimoire.id,
          "rewards" =>
            Enum.map(spells, fn spell ->
              %{
                "kind" => "spell",
                "id" => spell.id,
                "name" => spell.name,
                "school" => Atom.to_string(spell.school)
              }
            end)
        }

        updated_enrollment =
          enrollment
          |> Enrollment.changeset(%{
            metadata: Map.put(enrollment.metadata || %{}, "starter_outcomes", starter_outcomes)
          })
          |> Repo.update!()

        %{
          character: character,
          enrollment: updated_enrollment,
          starter_outcomes: starter_outcomes
        }

      starter_outcomes ->
        %{character: character, enrollment: enrollment, starter_outcomes: starter_outcomes}
    end
  end

  def grant!(%Character{} = character, %Enrollment{} = enrollment, _specialization, _outcome_tier) do
    %{character: character, enrollment: enrollment, starter_outcomes: summary(enrollment)}
  end

  @doc "Returns the persisted graduation receipt, if this enrollment created one."
  def summary(%Enrollment{} = enrollment) do
    case Map.get(enrollment.metadata || %{}, "starter_outcomes") do
      %{} = starter_outcomes -> starter_outcomes
      _other -> nil
    end
  end

  @doc "Returns the Academy recipe codes durably unlocked for a character."
  def recipe_unlocks(%Character{} = character) do
    metadata = character.metadata || %{}

    metadata
    |> Map.get(@recipe_unlocks_key, [])
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  @doc "Creates the real spell selected as a valedictorian's graduation bonus."
  def grant_valedictorian_spell!(%Character{} = character, %Enrollment{} = _enrollment, school) do
    settings = quality_settings(:refined)

    attrs =
      school
      |> wizard_spell_attrs(:laureate, :refined, settings)
      |> Map.update!(:tags, &(&1 ++ ["valedictorian"]))
      |> Map.update!(:narrative_tags, &(&1 ++ ["valedictorian_bonus"]))

    create_starter_spell!(character, attrs)
  end

  defp grant_track!(:wizardry, character, enrollment, specialization, quality) do
    settings = quality_settings(quality)

    spells =
      [
        wizard_spell_attrs(specialization.primary_school, :bolt, quality, settings),
        wizard_spell_attrs(specialization.secondary_school, :ward, quality, settings),
        wizard_spell_attrs(specialization.primary_school, :snare, quality, settings)
      ]
      |> Enum.map(&create_starter_spell!(character, &1))

    grimoire = academy_grimoire!(character, enrollment)
    inscribe_starter_spells!(grimoire, spells)

    rewards =
      Enum.map(spells, fn spell ->
        %{
          "kind" => "spell",
          "id" => spell.id,
          "name" => spell.name,
          "school" => Atom.to_string(spell.school)
        }
      end)

    {character, rewards, %{"grimoire_id" => grimoire.id}}
  end

  defp grant_track!(:mastery, character, enrollment, _specialization, quality) do
    templates = mastery_starter_templates(quality) |> Enum.map(&get_or_create_item_template!/1)

    rewards =
      Enum.map(templates, fn template ->
        {:ok, inventory_item} =
          Inventory.grant_item(character, template, %{
            metadata: %{
              "source" => "academy_starter_outcome",
              "enrollment_id" => enrollment.id
            }
          })

        %{
          "kind" => "tool",
          "inventory_item_id" => inventory_item.id,
          "code" => template.code,
          "name" => template.name
        }
      end)

    {character, rewards, %{}}
  end

  defp grant_track!(:alchemy, character, enrollment, _specialization, quality) do
    settings = quality_settings(quality)
    reagent = get_or_create_item_template!(alchemy_reagent_template(quality))

    recipes =
      alchemy_starter_recipes(quality, reagent)
      |> Enum.map(fn recipe_attrs ->
        result_item_template =
          recipe_attrs
          |> Map.fetch!(:result_item_template)
          |> get_or_create_item_template!()

        recipe_attrs
        |> Map.put(:result_item_template, result_item_template)
        |> get_or_create_recipe!()
      end)

    {:ok, _inventory_item} =
      Inventory.grant_item(character, reagent, %{
        quantity: settings.starter_reagents,
        metadata: %{
          "source" => "academy_starter_outcome",
          "enrollment_id" => enrollment.id
        }
      })

    updated_character = unlock_recipes!(character, recipes)

    rewards =
      Enum.map(recipes, fn recipe ->
        %{
          "kind" => "recipe",
          "id" => recipe.id,
          "code" => recipe.code,
          "name" => recipe.name
        }
      end)

    {updated_character, rewards,
     %{
       "starter_reagent" => %{
         "code" => reagent.code,
         "name" => reagent.name,
         "quantity" => settings.starter_reagents
       }
     }}
  end

  defp grant_track!(_track, character, _enrollment, _specialization, _quality),
    do: {character, [], %{}}

  defp quality_for(%Enrollment{} = enrollment, outcome_tier) do
    gpa = MMGO.Academy.gpa_for_enrollment(enrollment.id)

    cond do
      outcome_tier == :probation -> :provisional
      is_number(gpa) and gpa >= 85 -> :refined
      is_number(gpa) and gpa >= 65 -> :standard
      true -> :provisional
    end
  end

  defp quality_settings(quality), do: Map.fetch!(@quality_settings, quality)

  defp wizard_spell_attrs(school, kind, quality, settings) do
    school_presentation =
      Map.get(@school_presentations, school, %{label: "Неизвестная школа", formula: "Arcanum"})

    school_name = school_presentation.label
    school_formula = school_presentation.formula
    quality_code = Atom.to_string(quality)

    {name_suffix, formula_suffix, description, targeting, delivery_form, effect} =
      case kind do
        :bolt ->
          {
            "Импульс",
            "Ictus",
            "Собранный на практике Академии импульс школы #{school_name}.",
            :enemy,
            :single_target,
            %{applies_to: :target, state: "impact", duration: 0}
          }

        :ward ->
          {
            "Покров",
            "Tutela",
            "Защитная печать, выверенная в академическом практикуме.",
            :self,
            :self,
            %{applies_to: :caster, state: "shielded", duration: 2}
          }

        :snare ->
          {
            "Узел",
            "Nodus",
            "Контрольная вязь #{school_name}, рассчитанная на одинокую цель.",
            :enemy,
            :single_target,
            %{applies_to: :target, state: "trapped", duration: 1}
          }

        :laureate ->
          {
            "Лауреатская печать",
            "Laurea",
            "Именная печать валедикториана, выданная Академией в знак высшего результата.",
            :self,
            :self,
            %{applies_to: :caster, state: "empowered", duration: 2}
          }
      end

    %{
      name: "#{school_name} · #{name_suffix}",
      formula: "Academia #{school_formula} #{formula_suffix}",
      school: school,
      description: description,
      level_requirement: 1,
      fatigue_cost: if(kind == :ward, do: 2, else: 3),
      cooldown_turns: 1,
      targeting: targeting,
      delivery_form: delivery_form,
      tags: ["academy", "starter", quality_code],
      narrative_tags: ["academy_training"],
      effects: [
        Map.merge(effect, %{
          intensity:
            if(kind == :laureate,
              do: settings.empowerment_multiplier,
              else: settings.spell_intensity
            ),
          variance: if(kind == :laureate, do: 0, else: settings.spell_variance)
        })
      ],
      failure_profile: %{
        difficulty: settings.spell_difficulty,
        base_success_rate: settings.spell_success_rate,
        partial_success_rate: 8,
        backlash_damage: 0,
        volatility: 4
      }
    }
  end

  defp create_starter_spell!(%Character{} = character, attrs) do
    {:ok, spell} = Spells.create_spell(character, attrs)
    spell
  end

  defp academy_grimoire!(
         %Character{} = character,
         %Enrollment{} = enrollment,
         name \\ "Гримуар Академии"
       ) do
    existing =
      Repo.all(
        from grimoire in Grimoire,
          where: grimoire.owner_character_id == ^character.id,
          order_by: [asc: grimoire.inserted_at]
      )
      |> Enum.find(fn grimoire ->
        Map.get(grimoire.metadata || %{}, "source_enrollment_id") == enrollment.id
      end)

    existing ||
      %Grimoire{}
      |> Grimoire.changeset(%{
        owner_character_id: character.id,
        realm_id: character.realm_id,
        name: name,
        status: :draft,
        capacity: 5,
        weight: 1,
        metadata: %{
          "source" => "academy_starter_outcome",
          "source_enrollment_id" => enrollment.id
        }
      })
      |> Repo.insert!()
  end

  defp inscribe_starter_spells!(%Grimoire{} = grimoire, spells) do
    existing_entries =
      Repo.all(
        from entry in GrimoireEntry,
          where: entry.grimoire_id == ^grimoire.id,
          order_by: [asc: entry.slot_index]
      )

    known_spell_ids = MapSet.new(existing_entries, & &1.spell_id)
    next_slot = Enum.reduce(existing_entries, 0, &max(&1.slot_index, &2)) + 1

    Enum.reduce(spells, {known_spell_ids, next_slot}, fn spell, {known_ids, slot_index} ->
      if MapSet.member?(known_ids, spell.id) do
        {known_ids, slot_index}
      else
        %GrimoireEntry{}
        |> GrimoireEntry.changeset(%{
          grimoire_id: grimoire.id,
          spell_id: spell.id,
          slot_index: slot_index
        })
        |> Repo.insert!()

        {MapSet.put(known_ids, spell.id), slot_index + 1}
      end
    end)

    :ok
  end

  defp mastery_starter_templates(quality) do
    settings = quality_settings(quality)
    quality_code = Atom.to_string(quality)
    quality_label = settings.label |> String.capitalize()

    [
      %{
        code: "academy_mastery_#{quality_code}_field_hammer",
        name: "#{quality_label} полевой молот",
        item_type: :weapon,
        stackable: false,
        weight: 3,
        max_durability: settings.tool_durability,
        nutrition_units: 0,
        tags: ["academy", "starter", "mastery", quality_code],
        metadata: %{"academy_starter_track" => "mastery", "quality" => quality_code},
        actions: [
          %{
            key: "academy_hammer_strike",
            action_kind: :strike,
            targeting: :enemy,
            durability_cost: 1,
            effects: [
              %{
                applies_to: :target,
                state: "impact",
                intensity: settings.tool_intensity,
                variance: 1,
                duration: 0
              }
            ]
          }
        ]
      },
      %{
        code: "academy_mastery_#{quality_code}_buckler",
        name: "#{quality_label} академический баклер",
        item_type: :shield,
        stackable: false,
        weight: 2,
        max_durability: settings.tool_durability,
        nutrition_units: 0,
        tags: ["academy", "starter", "mastery", quality_code],
        metadata: %{"academy_starter_track" => "mastery", "quality" => quality_code},
        actions: [
          %{
            key: "academy_buckler_guard",
            action_kind: :raise_shield,
            targeting: :self,
            durability_cost: 1,
            effects: [
              %{
                applies_to: :caster,
                state: "shielded",
                intensity: settings.tool_intensity,
                variance: 1,
                duration: 2
              }
            ]
          }
        ]
      },
      %{
        code: "academy_mastery_#{quality_code}_repair_kit",
        name: "#{quality_label} набор мастера",
        item_type: :tool,
        stackable: false,
        weight: 2,
        max_durability: settings.tool_durability,
        nutrition_units: 0,
        tags: ["academy", "starter", "mastery", quality_code],
        metadata: %{"academy_starter_track" => "mastery", "quality" => quality_code},
        actions: [
          %{
            key: "academy_repair_focus",
            action_kind: :repair,
            targeting: :self,
            durability_cost: 1,
            effects: [
              %{
                applies_to: :caster,
                state: "empowered",
                intensity: settings.empowerment_multiplier,
                variance: 0,
                duration: 1
              }
            ]
          }
        ]
      }
    ]
  end

  defp alchemy_reagent_template(quality) do
    settings = quality_settings(quality)
    quality_code = Atom.to_string(quality)

    %{
      code: "academy_alchemy_#{quality_code}_reagent",
      name: "#{String.capitalize(settings.label)} реактив Академии",
      item_type: :ingredient,
      stackable: true,
      weight: 1,
      max_durability: 0,
      nutrition_units: 0,
      tags: ["academy", "starter", "alchemy", quality_code],
      metadata: %{"academy_starter_track" => "alchemy", "quality" => quality_code},
      actions: []
    }
  end

  defp alchemy_starter_recipes(quality, %ItemTemplate{} = reagent) do
    settings = quality_settings(quality)
    quality_code = Atom.to_string(quality)
    quality_label = String.capitalize(settings.label)

    [
      %{
        code: "academy_alchemy_#{quality_code}_mending_tonic",
        name: "#{quality_label} тоник восстановления",
        brew_time_game_days: 1,
        difficulty: max(1, 12 - settings.potion_intensity),
        required_tool_codes: [],
        result_quantity: 1,
        requirements: [%{item_template_id: reagent.id, quantity: 1}],
        metadata: %{"academy_starter_track" => "alchemy", "quality" => quality_code},
        result_item_template: %{
          code: "academy_alchemy_#{quality_code}_mending_tonic",
          name: "#{quality_label} тоник восстановления",
          item_type: :potion,
          stackable: true,
          weight: 1,
          max_durability: 0,
          nutrition_units: 0,
          tags: ["academy", "starter", "alchemy", quality_code],
          metadata: %{"academy_starter_track" => "alchemy", "quality" => quality_code},
          actions: [
            %{
              key: "academy_tonic_drink",
              action_kind: :deploy,
              targeting: :self,
              quantity_cost: 1,
              effects: [
                %{
                  applies_to: :caster,
                  state: "regenerating",
                  intensity: settings.potion_intensity,
                  variance: 1,
                  duration: 2
                }
              ]
            }
          ]
        }
      },
      %{
        code: "academy_alchemy_#{quality_code}_ward_phial",
        name: "#{quality_label} фиал покрова",
        brew_time_game_days: 1,
        difficulty: max(1, 14 - settings.potion_intensity),
        required_tool_codes: [],
        result_quantity: 1,
        requirements: [%{item_template_id: reagent.id, quantity: 1}],
        metadata: %{"academy_starter_track" => "alchemy", "quality" => quality_code},
        result_item_template: %{
          code: "academy_alchemy_#{quality_code}_ward_phial",
          name: "#{quality_label} фиал покрова",
          item_type: :potion,
          stackable: true,
          weight: 1,
          max_durability: 0,
          nutrition_units: 0,
          tags: ["academy", "starter", "alchemy", quality_code],
          metadata: %{"academy_starter_track" => "alchemy", "quality" => quality_code},
          actions: [
            %{
              key: "academy_phial_guard",
              action_kind: :deploy,
              targeting: :self,
              quantity_cost: 1,
              effects: [
                %{
                  applies_to: :caster,
                  state: "shielded",
                  intensity: settings.potion_intensity,
                  variance: 1,
                  duration: 2
                }
              ]
            }
          ]
        }
      },
      %{
        code: "academy_alchemy_#{quality_code}_dazing_flask",
        name: "#{quality_label} колба тумана",
        brew_time_game_days: 1,
        difficulty: max(1, 16 - settings.potion_intensity),
        required_tool_codes: [],
        result_quantity: 1,
        requirements: [%{item_template_id: reagent.id, quantity: 1}],
        metadata: %{"academy_starter_track" => "alchemy", "quality" => quality_code},
        result_item_template: %{
          code: "academy_alchemy_#{quality_code}_dazing_flask",
          name: "#{quality_label} колба тумана",
          item_type: :potion,
          stackable: true,
          weight: 1,
          max_durability: 0,
          nutrition_units: 0,
          tags: ["academy", "starter", "alchemy", quality_code],
          metadata: %{"academy_starter_track" => "alchemy", "quality" => quality_code},
          actions: [
            %{
              key: "academy_flask_throw",
              action_kind: :throw,
              targeting: :enemy,
              quantity_cost: 1,
              effects: [
                %{
                  applies_to: :target,
                  state: "blinded",
                  intensity: settings.potion_intensity,
                  variance: 1,
                  duration: 1
                }
              ]
            }
          ]
        }
      }
    ]
  end

  defp get_or_create_item_template!(attrs) do
    code = Map.fetch!(attrs, :code)

    case Repo.get_by(ItemTemplate, code: code) do
      %ItemTemplate{} = item_template ->
        item_template

      nil ->
        %ItemTemplate{}
        |> ItemTemplate.changeset(attrs)
        |> Repo.insert!(on_conflict: :nothing, conflict_target: :code)

        Repo.get_by!(ItemTemplate, code: code)
    end
  end

  defp get_or_create_recipe!(attrs) do
    code = Map.fetch!(attrs, :code)
    result_item_template = Map.fetch!(attrs, :result_item_template)

    case Repo.get_by(Recipe, code: code) do
      %Recipe{} = recipe ->
        Repo.preload(recipe, :result_item_template)

      nil ->
        recipe_attrs =
          attrs
          |> Map.delete(:result_item_template)
          |> Map.put(:result_item_template_id, result_item_template.id)

        %Recipe{}
        |> Recipe.changeset(recipe_attrs)
        |> Repo.insert!(on_conflict: :nothing, conflict_target: :code)

        Recipe
        |> Repo.get_by!(code: code)
        |> Repo.preload(:result_item_template)
    end
  end

  defp unlock_recipes!(%Character{} = character, recipes) do
    unlocks = Enum.uniq(recipe_unlocks(character) ++ Enum.map(recipes, & &1.code))

    character
    |> Character.changeset(%{
      metadata: Map.put(character.metadata || %{}, @recipe_unlocks_key, unlocks)
    })
    |> Repo.update!()
  end
end
