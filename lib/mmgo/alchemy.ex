defmodule MMGO.Alchemy do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.{Character, CharacterProfiles}
  alias MMGO.Academy
  alias MMGO.Academy.StarterOutcomes
  alias MMGO.Alchemy.{BrewJob, CompleteBrewJobWorker, Interpreter, Recipe, Workshop}
  alias MMGO.Bases.Base
  alias MMGO.Inventory
  alias MMGO.Inventory.{InventoryItem, ItemTemplate}
  alias MMGO.Notifications
  alias MMGO.Progression
  alias MMGO.Repo
  alias MMGO.Travel.Clock

  def get_workshop!(id), do: Repo.get!(Workshop, id)

  def get_workshop_for_character(character_id) when is_binary(character_id) do
    Repo.get_by(Workshop, owner_character_id: character_id, status: :active)
  end

  def list_recipes do
    Repo.all(
      from recipe in Recipe, order_by: [asc: recipe.inserted_at], preload: [:result_item_template]
    )
  end

  @doc "Lists recipes that the character has actually unlocked or can use by default."
  def list_recipes_for_character(%Character{} = character) do
    list_recipes()
    |> Enum.filter(&recipe_available_to_character?(character, &1))
  end

  @doc "Returns whether a recipe is available to this character's alchemy practice."
  def recipe_available_to_character?(%Character{} = character, %Recipe{} = recipe) do
    case Map.get(recipe.metadata || %{}, "academy_starter_track") do
      "alchemy" -> recipe.code in StarterOutcomes.recipe_unlocks(character)
      _other -> true
    end
  end

  def recipe_available_to_character?(_character, _recipe), do: false

  def get_recipe!(id), do: Recipe |> Repo.get!(id) |> Repo.preload(:result_item_template)

  def get_recipe_by_code(code) when is_binary(code) do
    Recipe
    |> Repo.get_by(code: code)
    |> case do
      nil -> nil
      recipe -> Repo.preload(recipe, :result_item_template)
    end
  end

  def list_brew_jobs_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from brew_job in BrewJob,
        where: brew_job.character_id == ^character_id,
        order_by: [desc: brew_job.inserted_at],
        preload: [:recipe, :workspace]
    )
  end

  def active_brew_job(character_id) when is_binary(character_id) do
    Repo.get_by(BrewJob, character_id: character_id, status: :active)
  end

  def create_workshop(%Character{} = character, attrs \\ %{}) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("owner_character_id", character.id)
      |> Map.put("realm_id", character.realm_id)

    Repo.transaction(fn ->
      character = lock_character!(character.id)
      validate_workshop_location!(character, Map.get(attrs, "location_id"))

      case %Workshop{} |> Workshop.changeset(attrs) |> Repo.insert() do
        {:ok, workshop} -> workshop
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def update_workshop(%Workshop{} = workshop, attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      workshop = lock_workshop!(workshop.id)
      character = lock_character!(workshop.owner_character_id)
      location_id = Map.get(attrs, "location_id", workshop.location_id)

      validate_workshop_location!(character, location_id)

      attrs =
        attrs
        |> Map.delete("owner_character_id")
        |> Map.delete("realm_id")

      case workshop |> Workshop.changeset(attrs) |> Repo.update() do
        {:ok, updated_workshop} -> updated_workshop
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction_result()
  end

  def create_recipe(attrs \\ %{}) do
    %Recipe{}
    |> Recipe.changeset(stringify_keys(attrs))
    |> Repo.insert()
  end

  @doc "Lists owned inventory ingredients that expose fixed alchemical primitives."
  def interpretable_ingredients(%Character{} = character) do
    character.id
    |> Inventory.list_inventory_for_character()
    |> Enum.filter(fn item ->
      item.item_template.item_type == :ingredient and
        normalize_primitives(item.item_template.metadata) != %{} and
        Inventory.available_quantity(item) > 0
    end)
  end

  @doc "Interprets an owned ingredient mixture, caches its formula, and starts one durable brew."
  def brew_from_ingredients(
        %Character{} = character,
        %Workshop{} = workspace,
        selections,
        opts \\ []
      ) do
    with :ok <- validate_interpreted_context(character, workspace),
         {:ok, mixture} <- build_mixture(character, selections),
         {:ok, recipe, interpretation, cached?} <-
           resolve_interpreted_recipe(character, mixture, opts),
         {:ok, brew_result} <- brew(character, workspace, recipe, 1, opts) do
      {:ok,
       brew_result
       |> Map.put(:interpretation, interpretation.result)
       |> Map.put(:ai_request, interpretation.ai_request)
       |> Map.put(:fallback?, interpretation.fallback?)
       |> Map.put(:formula_cached?, cached?)}
    end
  end

  defp resolve_interpreted_recipe(%Character{} = character, mixture, opts) do
    case get_recipe_by_code(interpreted_recipe_code(mixture)) do
      %Recipe{} = recipe ->
        interpretation = %{
          result: recipe.metadata["interpretation"] || %{},
          ai_request: nil,
          fallback?: recipe.metadata["fallback"] == true
        }

        {:ok, recipe, interpretation, true}

      nil ->
        with {:ok, interpretation} <- Interpreter.interpret(character, mixture, opts),
             {:ok, recipe, cached?} <- ensure_interpreted_recipe(mixture, interpretation) do
          {:ok, recipe, interpretation, cached?}
        end
    end
  end

  def brew(
        %Character{} = character,
        %Workshop{} = workspace,
        %Recipe{} = recipe,
        quantity,
        opts \\ []
      )
      when is_integer(quantity) do
    started_at = Keyword.get(opts, :started_at, DateTime.utc_now())

    Repo.transaction(fn ->
      character = lock_character!(character.id)
      workspace = lock_workshop!(workspace.id)
      recipe = get_recipe!(recipe.id)

      validate_brew_start!(character, workspace, recipe, quantity)

      consumed_ingredients = consume_ingredients!(character.id, recipe, quantity)
      completes_at = Clock.arrival_at(started_at, recipe.brew_time_game_days * quantity)

      brew_job =
        %BrewJob{}
        |> BrewJob.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          workspace_id: workspace.id,
          recipe_id: recipe.id,
          quantity: quantity,
          status: :active,
          started_at: started_at,
          completes_at: completes_at,
          metadata: %{"consumed_ingredients" => consumed_ingredients}
        })
        |> Repo.insert!()

      job =
        %{"brew_job_id" => brew_job.id}
        |> CompleteBrewJobWorker.new(
          schedule_in: max(DateTime.diff(completes_at, DateTime.utc_now(), :second), 0)
        )
        |> Oban.insert!()

      %{brew_job: Repo.preload(brew_job, [:recipe, :workspace]), worker_job: job}
    end)
    |> normalize_transaction_result()
  end

  def complete_brew_job_by_id(brew_job_id, opts \\ []) when is_binary(brew_job_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force, false)

    Repo.transaction(fn ->
      brew_job = lock_brew_job!(brew_job_id)
      character = lock_character!(brew_job.character_id)

      cond do
        brew_job.status != :active ->
          Repo.rollback(brew_job_changeset("brew job is not active"))

        not force? and DateTime.compare(now, brew_job.completes_at) == :lt ->
          Repo.rollback(brew_job_changeset("brew job is not due yet"))

        true ->
          recipe = get_recipe!(brew_job.recipe_id)

          {:ok, item_result} =
            Inventory.grant_item(character, recipe.result_item_template, %{
              quantity: brew_job.quantity * recipe.result_quantity
            })

          {:ok, %{character: updated_character}} =
            Progression.grant_xp(Repo, character, brew_xp(recipe, brew_job.quantity), %{
              "source" => "alchemy_brew_completion",
              "brew_job_id" => brew_job.id,
              "recipe_id" => recipe.id,
              "granted_at" => now
            })

          updated_brew_job =
            brew_job
            |> BrewJob.changeset(%{
              status: :completed,
              completed_at: now,
              yielded_quantity: brew_job.quantity * recipe.result_quantity,
              metadata:
                Map.put(
                  brew_job.metadata || %{},
                  "xp_awarded",
                  brew_xp(recipe, brew_job.quantity)
                )
            })
            |> Repo.update!()

          _ = Notifications.notify_brew_completed(updated_character, updated_brew_job)

          %{
            brew_job: Repo.preload(updated_brew_job, [:recipe, :workspace]),
            character: updated_character,
            item_result: item_result
          }
      end
    end)
    |> normalize_transaction_result()
  end

  def complete_due_brew_jobs(now \\ DateTime.utc_now()) do
    BrewJob
    |> where([brew_job], brew_job.status == :active and brew_job.completes_at <= ^now)
    |> Repo.all()
    |> Enum.map(fn brew_job -> complete_brew_job_by_id(brew_job.id, now: now, force: true) end)
  end

  defp validate_interpreted_context(%Character{} = character, %Workshop{} = workspace) do
    specialization = Academy.active_specialization(character.id)

    cond do
      workspace.status != :active ->
        {:error, workspace_changeset("workshop is not active")}

      workspace.owner_character_id != character.id ->
        {:error, workspace_changeset("workshop does not belong to this character")}

      character.realm_id != workspace.realm_id ->
        {:error, workspace_changeset("workshop must belong to the same realm")}

      character.current_location_id != workspace.location_id ->
        {:error, workspace_changeset("character must be at the workshop location")}

      is_nil(active_owned_base_at_location(character, workspace.location_id)) ->
        {:error, workspace_changeset("workshop must be installed at an active owned base")}

      active_brew_job(character.id) ->
        {:error, brew_job_changeset("character already has an active brew job")}

      (is_nil(specialization) or specialization.track != :alchemy) and
          not CharacterProfiles.mastered_track?(character, :alchemy) ->
        {:error, brew_job_changeset("character must be specialized in alchemy")}

      true ->
        :ok
    end
  end

  defp build_mixture(%Character{} = character, selections) do
    with {:ok, normalized} <- normalize_selections(selections),
         {:ok, ingredients} <- resolve_selected_ingredients(character, normalized) do
      ingredient_summary =
        ingredients
        |> Enum.group_by(& &1.item_template_id)
        |> Enum.map(fn {_template_id, selected_items} ->
          first = hd(selected_items)

          %{
            item_template_id: first.item_template_id,
            code: first.code,
            name: first.name,
            quantity: Enum.sum(Enum.map(selected_items, & &1.quantity)),
            primitives: first.primitives
          }
        end)
        |> Enum.sort_by(& &1.code)

      primitive_totals =
        Enum.reduce(ingredient_summary, %{}, fn ingredient, totals ->
          Enum.reduce(ingredient.primitives, totals, fn {primitive, amount}, inner_totals ->
            Map.update(inner_totals, primitive, amount * ingredient.quantity, fn current ->
              current + amount * ingredient.quantity
            end)
          end)
        end)

      fingerprint_payload = %{
        realm_id: character.realm_id,
        ingredients:
          Enum.map(ingredient_summary, fn ingredient ->
            %{
              code: ingredient.code,
              quantity: ingredient.quantity,
              primitives: ingredient.primitives
            }
          end)
      }

      fingerprint =
        fingerprint_payload
        |> Jason.encode!()
        |> then(&:crypto.hash(:sha256, &1))
        |> Elixir.Base.encode16(case: :lower)

      {:ok,
       %{
         fingerprint: fingerprint,
         ingredients: ingredient_summary,
         primitive_totals: primitive_totals
       }}
    end
  end

  defp normalize_selections(selections) when is_map(selections) do
    selections
    |> Enum.reduce_while({:ok, []}, fn {inventory_item_id, quantity}, {:ok, normalized} ->
      case normalize_selected_quantity(quantity) do
        :skip ->
          {:cont, {:ok, normalized}}

        {:ok, parsed} when is_binary(inventory_item_id) ->
          {:cont, {:ok, [%{inventory_item_id: inventory_item_id, quantity: parsed} | normalized]}}

        _invalid ->
          {:halt, {:error, brew_job_changeset("ingredient quantities are invalid")}}
      end
    end)
    |> validate_selection_bounds()
  end

  defp normalize_selections(selections) when is_list(selections) do
    selections
    |> Enum.reduce_while({:ok, []}, fn selection, {:ok, normalized} ->
      item_id = selection[:inventory_item_id] || selection["inventory_item_id"]
      quantity = selection[:quantity] || selection["quantity"]

      case normalize_selected_quantity(quantity) do
        {:ok, parsed} when is_binary(item_id) ->
          {:cont, {:ok, [%{inventory_item_id: item_id, quantity: parsed} | normalized]}}

        _invalid ->
          {:halt, {:error, brew_job_changeset("ingredient quantities are invalid")}}
      end
    end)
    |> validate_selection_bounds()
  end

  defp normalize_selections(_selections),
    do: {:error, brew_job_changeset("ingredient selection is required")}

  defp validate_selection_bounds({:error, _changeset} = error), do: error

  defp validate_selection_bounds({:ok, selections}) do
    selections = Enum.reverse(selections)

    cond do
      selections == [] ->
        {:error, brew_job_changeset("select at least one ingredient")}

      length(selections) > 6 ->
        {:error, brew_job_changeset("select at most six ingredients")}

      Enum.sum(Enum.map(selections, & &1.quantity)) > 12 ->
        {:error, brew_job_changeset("a brew may use at most twelve ingredient units")}

      true ->
        {:ok, selections}
    end
  end

  defp normalize_selected_quantity(value) when value in [nil, "", 0, "0"], do: :skip
  defp normalize_selected_quantity(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_selected_quantity(value) when is_binary(value) do
    case Integer.parse(value) do
      {quantity, ""} when quantity > 0 -> {:ok, quantity}
      _invalid -> :error
    end
  end

  defp normalize_selected_quantity(_value), do: :error

  defp resolve_selected_ingredients(%Character{} = character, selections) do
    inventory_by_id =
      character.id
      |> Inventory.list_inventory_for_character()
      |> Map.new(&{&1.id, &1})

    selections
    |> Enum.reduce_while({:ok, []}, fn selection, {:ok, resolved} ->
      case Map.get(inventory_by_id, selection.inventory_item_id) do
        %InventoryItem{} = item ->
          primitives = normalize_primitives(item.item_template.metadata)

          cond do
            item.item_template.item_type != :ingredient ->
              {:halt, {:error, brew_job_changeset("selected item is not an ingredient")}}

            primitives == %{} ->
              {:halt,
               {:error, brew_job_changeset("selected ingredient has no alchemical primitives")}}

            selection.quantity > Inventory.available_quantity(item) ->
              {:halt, {:error, brew_job_changeset("selected ingredient quantity is unavailable")}}

            true ->
              selected = %{
                inventory_item_id: item.id,
                item_template_id: item.item_template_id,
                code: item.item_template.code,
                name: item.item_template.name,
                quantity: selection.quantity,
                primitives: primitives
              }

              {:cont, {:ok, [selected | resolved]}}
          end

        nil ->
          {:halt, {:error, brew_job_changeset("selected ingredient is unavailable")}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  defp normalize_primitives(metadata) when is_map(metadata) do
    case Map.get(metadata, "alchemical_primitives") do
      primitives when is_map(primitives) ->
        primitives
        |> Enum.flat_map(fn
          {primitive, amount}
          when is_binary(primitive) and is_integer(amount) and amount > 0 and amount <= 10 ->
            if primitive in Interpreter.primitive_keys(), do: [{primitive, amount}], else: []

          _invalid ->
            []
        end)
        |> Map.new()

      _missing ->
        %{}
    end
  end

  defp normalize_primitives(_metadata), do: %{}

  defp ensure_interpreted_recipe(mixture, interpretation) do
    code = interpreted_recipe_code(mixture)

    case get_recipe_by_code(code) do
      %Recipe{} = recipe ->
        {:ok, recipe, true}

      nil ->
        Repo.transaction(fn ->
          case get_recipe_by_code(code) do
            %Recipe{} = recipe ->
              {recipe, true}

            nil ->
              item_template = ensure_interpreted_item_template!(code, mixture, interpretation)
              recipe = ensure_interpreted_recipe!(code, item_template, mixture, interpretation)
              {recipe, false}
          end
        end)
        |> case do
          {:ok, {recipe, cached?}} -> {:ok, recipe, cached?}
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end
    end
  end

  defp ensure_interpreted_item_template!(code, mixture, interpretation) do
    result = interpretation.result

    attrs = %{
      code: code,
      name: result["name"],
      item_type: :potion,
      stackable: true,
      weight: 1,
      max_durability: 0,
      nutrition_units: 0,
      tags: ["alchemy", "interpreted"],
      metadata: %{
        "alchemy_fingerprint" => mixture.fingerprint,
        "primitive_totals" => mixture.primitive_totals,
        "description" => result["description"],
        "fallback" => interpretation.fallback?
      },
      actions: [
        %{
          key: "use",
          action_kind: :throw,
          targeting: result["targeting"],
          quantity_cost: 1,
          durability_cost: 0,
          tags: ["alchemy"],
          effects: result["effects"]
        }
      ]
    }

    case Repo.get_by(ItemTemplate, code: code) do
      %ItemTemplate{} = template ->
        template

      nil ->
        case Inventory.create_item_template(attrs) do
          {:ok, template} -> template
          {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp ensure_interpreted_recipe!(code, item_template, mixture, interpretation) do
    result = interpretation.result

    requirements =
      Enum.map(mixture.ingredients, fn ingredient ->
        %{item_template_id: ingredient.item_template_id, quantity: ingredient.quantity}
      end)

    attrs = %{
      code: code,
      name: result["name"],
      result_item_template_id: item_template.id,
      brew_time_game_days: result["brew_time_game_days"],
      difficulty: result["difficulty"],
      required_tool_codes: [],
      result_quantity: 1,
      requirements: requirements,
      metadata: %{
        "interpreted_alchemy" => true,
        "ingredient_fingerprint" => mixture.fingerprint,
        "primitive_totals" => mixture.primitive_totals,
        "fallback" => interpretation.fallback?,
        "interpretation" => result,
        "ai_request_id" => interpretation.ai_request && interpretation.ai_request.id
      }
    }

    case create_recipe(attrs) do
      {:ok, recipe} -> Repo.preload(recipe, :result_item_template)
      {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
    end
  end

  defp interpreted_recipe_code(mixture),
    do: "alchemy_" <> String.slice(mixture.fingerprint, 0, 32)

  defp validate_brew_start!(
         %Character{} = character,
         %Workshop{} = workspace,
         %Recipe{} = recipe,
         quantity
       ) do
    specialization = Academy.active_specialization(character.id)

    cond do
      quantity <= 0 ->
        Repo.rollback(brew_job_changeset("quantity must be greater than zero"))

      workspace.status != :active ->
        Repo.rollback(workspace_changeset("workshop is not active"))

      workspace.owner_character_id != character.id ->
        Repo.rollback(workspace_changeset("workshop does not belong to this character"))

      character.realm_id != workspace.realm_id ->
        Repo.rollback(workspace_changeset("workshop must belong to the same realm"))

      character.current_location_id != workspace.location_id ->
        Repo.rollback(workspace_changeset("character must be at the workshop location"))

      is_nil(active_owned_base_at_location(character, workspace.location_id)) ->
        Repo.rollback(workspace_changeset("workshop must be installed at an active owned base"))

      active_brew_job(character.id) ->
        Repo.rollback(brew_job_changeset("character already has an active brew job"))

      (is_nil(specialization) or specialization.track != :alchemy) and
          not CharacterProfiles.mastered_track?(character, :alchemy) ->
        Repo.rollback(brew_job_changeset("character must be specialized in alchemy"))

      not recipe_available_to_character?(character, recipe) ->
        Repo.rollback(brew_job_changeset("recipe is not unlocked for this character"))

      recipe.required_tool_codes -- workspace.installed_tool_codes != [] ->
        Repo.rollback(workspace_changeset("workshop lacks required alchemy tools"))

      true ->
        validate_ingredient_availability!(character.id, recipe, quantity)
    end
  end

  defp validate_ingredient_availability!(character_id, %Recipe{} = recipe, quantity) do
    Enum.each(recipe.requirements, fn requirement ->
      total_available =
        InventoryItem
        |> where(
          [item],
          item.character_id == ^character_id and
            item.item_template_id == ^requirement.item_template_id and
            item.quantity - item.reserved_quantity > 0
        )
        |> Repo.all()
        |> Enum.reduce(0, fn item, total -> total + Inventory.available_quantity(item) end)

      if total_available < requirement.quantity * quantity do
        Repo.rollback(brew_job_changeset("missing required ingredients"))
      end
    end)
  end

  defp consume_ingredients!(character_id, %Recipe{} = recipe, quantity) do
    Enum.map(recipe.requirements, fn requirement ->
      quantity_needed = requirement.quantity * quantity

      {remaining, consumed_items} =
        InventoryItem
        |> where(
          [item],
          item.character_id == ^character_id and
            item.item_template_id == ^requirement.item_template_id and
            item.quantity - item.reserved_quantity > 0
        )
        |> order_by([item], asc: item.inserted_at)
        |> lock("FOR UPDATE")
        |> Repo.all()
        |> Enum.reduce_while({quantity_needed, []}, fn item, {remaining_needed, consumed_items} ->
          if remaining_needed <= 0 do
            {:halt, {remaining_needed, consumed_items}}
          else
            available = Inventory.available_quantity(item)
            taken = min(available, remaining_needed)
            updated_quantity = item.quantity - taken

            if updated_quantity == 0 do
              Repo.delete!(item)
            else
              item
              |> InventoryItem.changeset(%{
                quantity: updated_quantity,
                reserved_quantity: item.reserved_quantity
              })
              |> Repo.update!()
            end

            {:cont,
             {
               remaining_needed - taken,
               [
                 %{
                   "inventory_item_id" => item.id,
                   "quantity" => taken,
                   "item_template_id" => requirement.item_template_id
                 }
                 | consumed_items
               ]
             }}
          end
        end)

      if remaining > 0 do
        Repo.rollback(brew_job_changeset("ingredient consumption failed"))
      end

      %{
        "item_template_id" => requirement.item_template_id,
        "quantity" => quantity_needed,
        "consumed_items" => Enum.reverse(consumed_items)
      }
    end)
  end

  defp brew_xp(%Recipe{} = recipe, quantity) do
    max(quantity * (recipe.difficulty * 2), quantity * 5)
  end

  defp validate_workshop_location!(%Character{} = character, location_id) do
    cond do
      not is_binary(location_id) ->
        Repo.rollback(workspace_changeset("workshop location is required"))

      character.current_location_id != location_id ->
        Repo.rollback(workspace_changeset("character must be at the workshop location"))

      is_nil(active_owned_base_at_location(character, location_id)) ->
        Repo.rollback(workspace_changeset("workshop must be installed at an active owned base"))

      true ->
        :ok
    end
  end

  defp active_owned_base_at_location(%Character{} = character, location_id)
       when is_binary(location_id) do
    Repo.get_by(Base,
      owner_character_id: character.id,
      realm_id: character.realm_id,
      location_id: location_id,
      status: :active
    )
  end

  defp active_owned_base_at_location(_character, _location_id), do: nil

  defp lock_character!(character_id) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_workshop!(workshop_id) do
    Workshop
    |> where([workspace], workspace.id == ^workshop_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp lock_brew_job!(brew_job_id) do
    BrewJob
    |> where([brew_job], brew_job.id == ^brew_job_id)
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

  defp workspace_changeset(message) do
    %Workshop{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end

  defp brew_job_changeset(message) do
    %BrewJob{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
