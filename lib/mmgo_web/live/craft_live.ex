defmodule MMGOWeb.CraftLive do
  @moduledoc """
  Scoped crafting workshop and durable craft-job surface.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket),
    do: load_craft(socket, socket.assigns.current_scope.character)

  @impl true
  def handle_event("create_workshop", %{"craft_workshop" => attrs}, socket) do
    case Play.create_crafting_workshop(socket.assigns.character, attrs) do
      {:ok, _state} ->
        {:noreply, socket |> put_flash(:info, "Верстак подготовлен.") |> refresh_craft()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("craft", %{"craft" => params}, socket) do
    with {:ok, quantity} <- parse_positive(params["quantity"]),
         {:ok, _state} <-
           Play.start_craft(socket.assigns.character, params["recipe_id"], quantity) do
      {:noreply,
       socket
       |> put_flash(:info, "Работа начата; результат появится по игровому времени.")
       |> refresh_craft()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("collect", %{"job-id" => job_id}, socket) do
    case Play.collect_craft(socket.assigns.character, job_id) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Работа завершена, результат добавлен в котомку.")
         |> refresh_craft()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_craft(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="craft-screen" class="game-root min-h-full px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-5">
          <.link id="craft-back-to-base" navigate={~p"/base"} class="map-back-link">← База</.link>
          <header class="rounded-xl border border-orange-500/25 bg-stone-900/80 p-6 shadow-xl">
            <p class="text-xs uppercase tracking-[0.22em] text-orange-300/70">
              мастерская · {@base.name}
            </p>
            <h1 class="mt-2 font-serif text-3xl text-orange-100">Верстак</h1>
            <p class="mt-2 text-sm text-stone-400">
              Инструменты из котомки: {tool_list(@installed_tool_codes)}
            </p>
          </header>

          <div
            :if={@error}
            id="craft-error"
            class="rounded-md border border-red-500/50 bg-red-950/30 px-4 py-3 text-sm text-red-200"
          >
            {@error}
          </div>

          <section
            :if={is_nil(@workspace)}
            id="craft-workshop-setup"
            class="rounded-xl border border-orange-500/25 bg-orange-950/15 p-6"
          >
            <h2 class="font-serif text-2xl text-orange-100">Оборудовать верстак</h2>
            <p class="mt-2 text-sm text-stone-400">
              Коды установленных инструментов берутся из вашей реальной котомки.
            </p>
            <.form
              for={@workshop_form}
              id="craft-workshop-form"
              phx-submit="create_workshop"
              class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-end"
            >
              <.input
                field={@workshop_form[:name]}
                type="text"
                label="Название"
                placeholder="Верстак"
              />
              <button
                id="craft-create-workshop"
                type="submit"
                class="mb-4 rounded-md bg-orange-300 px-4 py-3 font-semibold text-stone-950 hover:bg-orange-200"
              >
                Оборудовать
              </button>
            </.form>
          </section>

          <section
            :if={@workspace && not @workspace_here?}
            id="craft-workshop-away"
            class="rounded-xl border border-amber-500/25 bg-amber-950/15 p-6 text-sm text-amber-100"
          >
            Ваш активный верстак находится в другом месте. Вернитесь к нему, чтобы начать работу.
          </section>

          <section
            :if={@workspace_here?}
            id="craft-start"
            class="rounded-xl border border-orange-500/25 bg-orange-950/15 p-6"
          >
            <h2 class="font-serif text-2xl text-orange-100">Начать работу</h2>
            <p :if={@recipes == []} id="craft-recipes-empty" class="mt-3 text-sm text-stone-400">
              Для этого мира ещё не записаны чертежи.
            </p>
            <.form
              :if={@recipes != []}
              for={@craft_form}
              id="craft-form"
              phx-submit="craft"
              class="mt-4 grid gap-3 sm:grid-cols-[1fr_8rem_auto] sm:items-end"
            >
              <.input
                field={@craft_form[:recipe_id]}
                type="select"
                label="Чертёж"
                prompt="Выберите чертёж"
                options={@recipe_options}
              />
              <.input
                field={@craft_form[:quantity]}
                type="number"
                label="Количество"
                min="1"
                inputmode="numeric"
              />
              <button
                id="craft-start-job"
                type="submit"
                class="mb-4 rounded-md bg-orange-300 px-4 py-3 font-semibold text-stone-950 hover:bg-orange-200"
              >
                Начать
              </button>
            </.form>
          </section>

          <section id="craft-jobs" class="rounded-xl border border-stone-700 bg-stone-900/70 p-6">
            <h2 class="font-serif text-xl text-stone-100">Работы</h2>
            <p :if={@jobs == []} id="craft-jobs-empty" class="mt-3 text-sm text-stone-400">
              Нет активных или завершённых работ.
            </p>
            <article
              :for={job <- @jobs}
              id={"craft-job-#{job.id}"}
              class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-stone-700 bg-stone-950/45 p-3 text-sm"
            >
              <div>
                <p class="font-medium text-stone-100">{job.recipe.name} ×{job.quantity}</p>
                <p class="text-stone-400">
                  {job.status} · готовность {format_time(job.completes_at)}
                </p>
              </div>
              <button
                :if={job.status == :active}
                id={"craft-collect-#{job.id}"}
                type="button"
                phx-click="collect"
                phx-value-job-id={job.id}
                class="rounded border border-orange-300/50 px-3 py-1.5 text-orange-100"
              >
                Проверить готовность
              </button>
            </article>
          </section>

          <button
            id="craft-refresh"
            type="button"
            phx-click="refresh"
            class="text-sm text-orange-200 underline decoration-orange-500/40 underline-offset-4"
          >
            Обновить верстак
          </button>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp load_craft(socket, character) do
    case Play.craft_state(character) do
      {:ok, state} ->
        {:ok,
         socket |> assign(:page_title, "Верстак") |> assign(:error, nil) |> assign_craft(state)}

      {:error, :active_base_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Верстак доступен только на активной базе.")
         |> push_navigate(to: ~p"/base")}

      {:error, :travelling} ->
        {:ok, push_navigate(socket, to: ~p"/travel")}

      {:error, _reason} ->
        {:ok, push_navigate(socket, to: ~p"/base")}
    end
  end

  defp refresh_craft(socket) do
    case Play.craft_state(socket.assigns.character) do
      {:ok, state} -> socket |> assign(:error, nil) |> assign_craft(state)
      {:error, :active_base_not_found} -> push_navigate(socket, to: ~p"/base")
      {:error, :travelling} -> push_navigate(socket, to: ~p"/travel")
      {:error, _reason} -> assign(socket, :error, "Верстак сейчас недоступен.")
    end
  end

  defp assign_craft(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:base, state.base)
    |> assign(:workspace, state.workspace)
    |> assign(:workspace_here?, state.workspace_here?)
    |> assign(:recipes, state.recipes)
    |> assign(:jobs, state.jobs)
    |> assign(:installed_tool_codes, state.installed_tool_codes)
    |> assign(:recipe_options, Enum.map(state.recipes, &{&1.name, &1.id}))
    |> assign(:workshop_form, to_form(%{"name" => ""}, as: :craft_workshop))
    |> assign(:craft_form, to_form(%{"recipe_id" => "", "quantity" => "1"}, as: :craft))
  end

  defp parse_positive(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _other -> {:error, :invalid_quantity}
    end
  end

  defp parse_positive(_value), do: {:error, :invalid_quantity}
  defp tool_list([]), do: "нет"
  defp tool_list(codes), do: Enum.join(codes, ", ")
  defp format_time(nil), do: "ожидает расчёта"
  defp format_time(time), do: Calendar.strftime(time, "%d.%m %H:%M UTC")

  defp error_message(:active_base_not_found), do: "Верстак доступен только на активной базе."
  defp error_message(:crafting_workshop_exists), do: "У вас уже есть активный верстак."
  defp error_message(:crafting_workshop_not_here), do: "Этот верстак находится в другом месте."
  defp error_message(:craft_recipe_not_found), do: "Чертёж больше недоступен."
  defp error_message(:craft_job_not_found), do: "Работа больше недоступна."
  defp error_message(:invalid_quantity), do: "Укажите положительное количество."

  defp error_message(_reason),
    do: "Команда не выполнена: проверьте специализацию, инструменты и материалы."
end
