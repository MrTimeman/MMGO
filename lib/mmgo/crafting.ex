defmodule MMGO.Crafting do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Academy
  alias MMGO.Crafting.{CompleteCraftJobWorker, CraftJob, Recipe, Workshop}
  alias MMGO.Inventory
  alias MMGO.Inventory.InventoryItem
  alias MMGO.Notifications
  alias MMGO.Repo
  alias MMGO.Travel.Clock

  def get_workshop!(id), do: Repo.get!(Workshop, id)

  def get_workshop_for_character(character_id) when is_binary(character_id) do
    Repo.get_by(Workshop, owner_character_id: character_id, status: :active)
  end

  def list_recipes do
    Repo.all(
      from recipe in Recipe,
        order_by: [asc: recipe.inserted_at],
        preload: [:result_item_template]
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

  def list_craft_jobs_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from craft_job in CraftJob,
        where: craft_job.character_id == ^character_id,
        order_by: [desc: craft_job.inserted_at],
        preload: [:recipe, :workspace]
    )
  end

  def active_craft_job(character_id) when is_binary(character_id) do
    Repo.get_by(CraftJob, character_id: character_id, status: :active)
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

  def craft(
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

      validate_craft_start!(character, workspace, recipe, quantity)

      consumed_materials = consume_materials!(character.id, recipe, quantity)
      completes_at = Clock.arrival_at(started_at, recipe.craft_time_game_days * quantity)

      craft_job =
        %CraftJob{}
        |> CraftJob.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          workspace_id: workspace.id,
          recipe_id: recipe.id,
          quantity: quantity,
          status: :active,
          started_at: started_at,
          completes_at: completes_at,
          metadata: %{"consumed_materials" => consumed_materials}
        })
        |> Repo.insert!()

      job =
        %{"craft_job_id" => craft_job.id}
        |> CompleteCraftJobWorker.new(
          schedule_in: max(DateTime.diff(completes_at, DateTime.utc_now(), :second), 0)
        )
        |> Oban.insert!()

      %{craft_job: Repo.preload(craft_job, [:recipe, :workspace]), worker_job: job}
    end)
    |> normalize_transaction_result()
  end

  def complete_craft_job_by_id(craft_job_id, opts \\ []) when is_binary(craft_job_id) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    force? = Keyword.get(opts, :force, false)

    Repo.transaction(fn ->
      craft_job = lock_craft_job!(craft_job_id)
      character = lock_character!(craft_job.character_id)

      cond do
        craft_job.status != :active ->
          Repo.rollback(craft_job_changeset("craft job is not active"))

        not force? and DateTime.compare(now, craft_job.completes_at) == :lt ->
          Repo.rollback(craft_job_changeset("craft job is not due yet"))

        true ->
          recipe = get_recipe!(craft_job.recipe_id)

          {:ok, item_result} =
            Inventory.grant_item(character, recipe.result_item_template, %{
              quantity: craft_job.quantity * recipe.result_quantity,
              durability: recipe.result_durability
            })

          updated_character =
            character
            |> Character.changeset(%{xp: character.xp + craft_xp(recipe, craft_job.quantity)})
            |> Repo.update!()

          updated_craft_job =
            craft_job
            |> CraftJob.changeset(%{
              status: :completed,
              completed_at: now,
              yielded_quantity: craft_job.quantity * recipe.result_quantity,
              metadata:
                Map.put(
                  craft_job.metadata || %{},
                  "xp_awarded",
                  craft_xp(recipe, craft_job.quantity)
                )
            })
            |> Repo.update!()

          _ = Notifications.notify_craft_completed(updated_character, updated_craft_job)

          %{
            craft_job: Repo.preload(updated_craft_job, [:recipe, :workspace]),
            character: updated_character,
            item_result: item_result
          }
      end
    end)
    |> normalize_transaction_result()
  end

  def complete_due_craft_jobs(now \\ DateTime.utc_now()) do
    CraftJob
    |> where([craft_job], craft_job.status == :active and craft_job.completes_at <= ^now)
    |> Repo.all()
    |> Enum.map(fn craft_job -> complete_craft_job_by_id(craft_job.id, now: now, force: true) end)
  end

  defp validate_craft_start!(
         %Character{} = character,
         %Workshop{} = workspace,
         %Recipe{} = recipe,
         quantity
       ) do
    specialization = Academy.active_specialization(character.id)

    cond do
      quantity <= 0 ->
        Repo.rollback(craft_job_changeset("quantity must be greater than zero"))

      workspace.status != :active ->
        Repo.rollback(workspace_changeset("workshop is not active"))

      workspace.owner_character_id != character.id ->
        Repo.rollback(workspace_changeset("workshop does not belong to this character"))

      character.realm_id != workspace.realm_id ->
        Repo.rollback(workspace_changeset("workshop must belong to the same realm"))

      character.current_location_id != workspace.location_id ->
        Repo.rollback(workspace_changeset("character must be at the workshop location"))

      active_craft_job(character.id) ->
        Repo.rollback(craft_job_changeset("character already has an active craft job"))

      is_nil(specialization) or specialization.track != :mastery ->
        Repo.rollback(craft_job_changeset("character must be specialized in mastery"))

      recipe.required_tool_codes -- workspace.installed_tool_codes != [] ->
        Repo.rollback(workspace_changeset("workshop lacks required crafting tools"))

      true ->
        validate_material_availability!(character.id, recipe, quantity)
    end
  end

  defp validate_material_availability!(character_id, %Recipe{} = recipe, quantity) do
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
        Repo.rollback(craft_job_changeset("missing required crafting materials"))
      end
    end)
  end

  defp consume_materials!(character_id, %Recipe{} = recipe, quantity) do
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
        Repo.rollback(craft_job_changeset("material consumption failed"))
      end

      %{
        "item_template_id" => requirement.item_template_id,
        "quantity" => quantity_needed,
        "consumed_items" => Enum.reverse(consumed_items)
      }
    end)
  end

  defp craft_xp(%Recipe{} = recipe, quantity) do
    max(quantity * (recipe.difficulty * 3), quantity * 6)
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

  defp lock_craft_job!(craft_job_id) do
    CraftJob
    |> where([craft_job], craft_job.id == ^craft_job_id)
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

  defp craft_job_changeset(message) do
    %CraftJob{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
