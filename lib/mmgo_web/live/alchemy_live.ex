defmodule MMGOWeb.AlchemyLive do
  @moduledoc """
  Scoped alchemy workshop and durable brew-job surface.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket),
    do: load_alchemy(socket, socket.assigns.current_scope.character)

  @impl true
  def handle_event("create_workshop", %{"alchemy_workshop" => attrs}, socket) do
    case Play.create_alchemy_workshop(socket.assigns.character, attrs) do
      {:ok, _state} ->
        {:noreply,
         socket |> put_flash(:info, "Алхимический стол подготовлен.") |> refresh_alchemy()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("brew", %{"brew" => params}, socket) do
    with {:ok, _state} <-
           Play.start_interpreted_brew(
             socket.assigns.character,
             Map.get(params, "ingredients", %{})
           ) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "Свойства ингредиентов истолкованы; варка начата по игровому времени."
       )
       |> refresh_alchemy()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("collect", %{"job-id" => job_id}, socket) do
    case Play.collect_brew(socket.assigns.character, job_id) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Варка завершена, результат добавлен в котомку.")
         |> refresh_alchemy()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_alchemy(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="alchemy-screen" class="game-root min-h-full px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-5">
          <.link id="alchemy-back-to-base" navigate={~p"/base"} class="map-back-link">← База</.link>
          <header class="rounded-xl border border-violet-500/25 bg-stone-900/80 p-6 shadow-xl">
            <p class="text-xs uppercase tracking-[0.22em] text-violet-300/70">
              алхимия · {@base.name}
            </p>
            <h1 class="mt-2 font-serif text-3xl text-violet-100">Алхимический стол</h1>
            <p class="mt-2 text-sm text-stone-400">
              Инструменты из котомки: {tool_list(@installed_tool_codes)}
            </p>
          </header>

          <div
            :if={@error}
            id="alchemy-error"
            class="rounded-md border border-red-500/50 bg-red-950/30 px-4 py-3 text-sm text-red-200"
          >
            {@error}
          </div>

          <section
            :if={is_nil(@workspace)}
            id="alchemy-workshop-setup"
            class="rounded-xl border border-violet-500/25 bg-violet-950/15 p-6"
          >
            <h2 class="font-serif text-2xl text-violet-100">Оборудовать стол</h2>
            <p class="mt-2 text-sm text-stone-400">
              Установленные коды инструментов берутся только из вашей реальной котомки.
            </p>
            <.form
              for={@workshop_form}
              id="alchemy-workshop-form"
              phx-submit="create_workshop"
              class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-end"
            >
              <.input
                field={@workshop_form[:name]}
                type="text"
                label="Название"
                placeholder="Алхимический стол"
              />
              <button
                id="alchemy-create-workshop"
                type="submit"
                class="mb-4 rounded-md bg-violet-300 px-4 py-3 font-semibold text-stone-950 hover:bg-violet-200"
              >
                Оборудовать
              </button>
            </.form>
          </section>

          <section
            :if={@workspace && not @workspace_here?}
            id="alchemy-workshop-away"
            class="rounded-xl border border-amber-500/25 bg-amber-950/15 p-6 text-sm text-amber-100"
          >
            Ваш активный стол находится в другом месте. Вернитесь к нему, чтобы начать новую варку.
          </section>

          <section
            :if={@workspace_here?}
            id="alchemy-brew"
            class="rounded-xl border border-violet-500/25 bg-violet-950/15 p-6"
          >
            <h2 class="font-serif text-2xl text-violet-100">Начать варку</h2>
            <p class="mt-2 text-sm leading-6 text-stone-400">
              Выберите до шести ингредиентов. Мир передаст ИИ только их неизменные примитивы,
              а движок отклонит любое новое или слишком сильное состояние.
            </p>
            <p
              :if={@ingredients == []}
              id="alchemy-ingredients-empty"
              class="mt-3 text-sm text-stone-400"
            >
              В котомке нет ингредиентов с алхимическими примитивами.
            </p>
            <.form
              :if={@ingredients != []}
              for={@brew_form}
              id="alchemy-brew-form"
              phx-submit="brew"
              class="mt-4 space-y-3"
            >
              <div id="alchemy-ingredient-list" class="space-y-2">
                <div
                  :for={item <- @ingredients}
                  id={"alchemy-ingredient-#{item.id}"}
                  class="grid gap-3 rounded-lg border border-violet-400/15 bg-stone-950/45 p-3 sm:grid-cols-[1fr_7rem] sm:items-end"
                >
                  <div>
                    <p class="font-medium text-stone-100">
                      {item.item_template.name} · доступно {item.quantity - item.reserved_quantity}
                    </p>
                    <p class="mt-1 text-xs text-violet-200/70">
                      {primitive_list(item.item_template.metadata)}
                    </p>
                  </div>
                  <.input
                    id={"alchemy-ingredient-quantity-#{item.id}"}
                    name={"brew[ingredients][#{item.id}]"}
                    value="0"
                    type="number"
                    label="В котёл"
                    min="0"
                    max={item.quantity - item.reserved_quantity}
                    inputmode="numeric"
                    class="w-full rounded-xl border border-violet-300/30 bg-stone-950 px-3 py-2 text-stone-100 outline-none transition focus:border-violet-200 focus:ring-2 focus:ring-violet-400/20"
                  />
                </div>
              </div>
              <button
                id="alchemy-start-brew"
                type="submit"
                class="rounded-md bg-violet-300 px-4 py-3 font-semibold text-stone-950 transition hover:bg-violet-200"
              >
                Истолковать и поставить
              </button>
            </.form>
          </section>

          <section id="alchemy-jobs" class="rounded-xl border border-stone-700 bg-stone-900/70 p-6">
            <h2 class="font-serif text-xl text-stone-100">Варки</h2>
            <p :if={@jobs == []} id="alchemy-jobs-empty" class="mt-3 text-sm text-stone-400">
              Нет активных или завершённых варок.
            </p>
            <article
              :for={job <- @jobs}
              id={"alchemy-job-#{job.id}"}
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
                id={"alchemy-collect-#{job.id}"}
                type="button"
                phx-click="collect"
                phx-value-job-id={job.id}
                class="rounded border border-violet-300/50 px-3 py-1.5 text-violet-100"
              >
                Проверить готовность
              </button>
            </article>
          </section>

          <button
            id="alchemy-refresh"
            type="button"
            phx-click="refresh"
            class="text-sm text-violet-200 underline decoration-violet-500/40 underline-offset-4"
          >
            Обновить стол
          </button>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp load_alchemy(socket, character) do
    case Play.alchemy_state(character) do
      {:ok, state} ->
        {:ok,
         socket |> assign(:page_title, "Алхимия") |> assign(:error, nil) |> assign_alchemy(state)}

      {:error, :active_base_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Алхимия доступна только на активной базе.")
         |> push_navigate(to: ~p"/base")}

      {:error, :travelling} ->
        {:ok, push_navigate(socket, to: ~p"/travel")}

      {:error, _reason} ->
        {:ok, push_navigate(socket, to: ~p"/base")}
    end
  end

  defp refresh_alchemy(socket) do
    case Play.alchemy_state(socket.assigns.character) do
      {:ok, state} -> socket |> assign(:error, nil) |> assign_alchemy(state)
      {:error, :active_base_not_found} -> push_navigate(socket, to: ~p"/base")
      {:error, :travelling} -> push_navigate(socket, to: ~p"/travel")
      {:error, _reason} -> assign(socket, :error, "Алхимический стол сейчас недоступен.")
    end
  end

  defp assign_alchemy(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:base, state.base)
    |> assign(:workspace, state.workspace)
    |> assign(:workspace_here?, state.workspace_here?)
    |> assign(:recipes, state.recipes)
    |> assign(:ingredients, state.ingredients)
    |> assign(:jobs, state.jobs)
    |> assign(:installed_tool_codes, state.installed_tool_codes)
    |> assign(:workshop_form, to_form(%{"name" => ""}, as: :alchemy_workshop))
    |> assign(:brew_form, to_form(%{}, as: :brew))
  end

  defp tool_list([]), do: "нет"
  defp tool_list(codes), do: Enum.join(codes, ", ")

  defp primitive_list(metadata) do
    metadata
    |> Map.get("alchemical_primitives", %{})
    |> Enum.sort_by(fn {primitive, _amount} -> primitive end)
    |> Enum.map_join(" · ", fn {primitive, amount} -> "#{primitive} #{amount}" end)
  end

  defp format_time(nil), do: "ожидает расчёта"
  defp format_time(time), do: Calendar.strftime(time, "%d.%m %H:%M UTC")

  defp error_message(:active_base_not_found), do: "Алхимия доступна только на активной базе."
  defp error_message(:alchemy_workshop_exists), do: "У вас уже есть активный алхимический стол."
  defp error_message(:alchemy_workshop_not_here), do: "Этот стол находится в другом месте."
  defp error_message(:alchemy_recipe_not_found), do: "Рецепт больше недоступен."
  defp error_message(:brew_job_not_found), do: "Варка больше недоступна."
  defp error_message(:invalid_quantity), do: "Укажите положительное количество."
  defp error_message(:invalid_ingredients), do: "Выберите доступные ингредиенты для варки."

  defp error_message(_reason),
    do: "Команда не выполнена: проверьте специализацию, инструменты и ингредиенты."
end
