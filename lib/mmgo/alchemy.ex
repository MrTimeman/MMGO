defmodule MMGO.Alchemy do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Academy
  alias MMGO.Alchemy.{BrewJob, CompleteBrewJobWorker, Recipe, Workshop}
  alias MMGO.Inventory
  alias MMGO.Inventory.InventoryItem
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

    %Workshop{}
    |> Workshop.changeset(attrs)
    |> Repo.insert()
  end

  def update_workshop(%Workshop{} = workshop, attrs) when is_map(attrs) do
    workshop
    |> Workshop.changeset(stringify_keys(attrs))
    |> Repo.update()
  end

  def create_recipe(attrs \\ %{}) do
    %Recipe{}
    |> Recipe.changeset(stringify_keys(attrs))
    |> Repo.insert()
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

      active_brew_job(character.id) ->
        Repo.rollback(brew_job_changeset("character already has an active brew job"))

      is_nil(specialization) or specialization.track != :alchemy ->
        Repo.rollback(brew_job_changeset("character must be specialized in alchemy"))

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
