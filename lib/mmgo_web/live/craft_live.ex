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
      <main id="craft-screen" class="game-screen crf-screen">
        <div class="crf-root">
          <.link id="craft-back-to-base" navigate={~p"/base"} class="crf-exit">
            ← вернуться на базу
          </.link>

          <div
            :if={@error}
            id="craft-error"
            class="crf-alert crf-alert--error"
          >
            {@error}
          </div>

          <section
            id="craft-workshop-scene"
            class="crf-workshop-scene"
            aria-label="Кузнечная мастерская"
          >
            <div class="crf-workshop-scene__room" aria-hidden="true">
              <div class="crf-lantern">
                <span class="crf-lantern__chain"></span>
                <span class="crf-lantern__cap"></span>
                <span class="crf-lantern__glass"></span>
                <span class="crf-lantern__base"></span>
              </div>

              <div class="crf-rear-bench">
                <span class="crf-rear-bench__top"></span>
                <span class="crf-grinder">
                  <span class="crf-grinder__wheel"></span>
                  <span class="crf-grinder__rest"></span>
                  <span class="crf-grinder__base"></span>
                </span>
              </div>

              <div class="crf-furnace">
                <span class="crf-furnace__hood"></span>
                <span class="crf-furnace__mouth">
                  <i></i><i></i><i></i>
                </span>
                <span class="crf-furnace__stone crf-furnace__stone--one"></span>
                <span class="crf-furnace__stone crf-furnace__stone--two"></span>
                <span class="crf-furnace__stone crf-furnace__stone--three"></span>
              </div>

              <div class="crf-bellows">
                <span class="crf-bellows__handle"></span>
                <span class="crf-bellows__body"></span>
                <span class="crf-bellows__nozzle"></span>
              </div>

              <div class="crf-scene-anvil">
                <span class="crf-scene-anvil__face"></span>
                <span class="crf-scene-anvil__waist"></span>
                <span class="crf-scene-anvil__foot"></span>
              </div>
            </div>

            <div class="crf-tool-rail" aria-hidden="true">
              <span class="crf-tool-rail__peg crf-tool-rail__peg--one"></span>
              <span class="crf-tool-rail__peg crf-tool-rail__peg--two"></span>
              <span class="crf-tool-rail__peg crf-tool-rail__peg--three"></span>
              <span class="crf-tool-rail__peg crf-tool-rail__peg--four"></span>
              <span class="crf-hanging-hammer">
                <span class="crf-hanging-hammer__head"></span>
                <span class="crf-hanging-hammer__haft"></span>
              </span>
            </div>
          </section>

          <header class="crf-head">
            <p class="crf-kicker">мастерская · {@base.name}</p>
            <h1 class="crf-title">
              {if @workspace, do: @workspace.name, else: "Верстак мастера"}
            </h1>
            <p class="crf-sub">
              Жар, железо и точная работа. Здесь чертёж становится вещью.
            </p>
          </header>

          <section class="crf-tools" aria-labelledby="craft-tools-title">
            <p id="craft-tools-title" class="crf-label">Инструменты на стене</p>
            <div class="crf-tools__row">
              <span
                :if={@installed_tool_codes == []}
                class="crf-tool crf-tool--missing"
              >
                <span class="crf-tool__mark">×</span> пока пусто
              </span>
              <span
                :for={code <- @installed_tool_codes}
                class="crf-tool crf-tool--owned"
              >
                <span class="crf-tool__mark">✓</span>
                {tool_code_label(code)}
              </span>
            </div>
          </section>

          <section
            :if={is_nil(@workspace)}
            id="craft-workshop-setup"
            class="crf-ledger crf-ledger--setup"
          >
            <span class="crf-ledger__pin" aria-hidden="true"></span>
            <p class="crf-ledger__eyebrow">запись мастера</p>
            <h2 class="crf-ledger__title">Оборудовать верстак</h2>
            <p class="crf-ledger__copy">
              Дайте рабочему месту имя. Инструменты будут отмечены по вашей настоящей котомке.
            </p>
            <.form
              for={@workshop_form}
              id="craft-workshop-form"
              phx-submit="create_workshop"
              class="crf-setup-form"
            >
              <.input
                field={@workshop_form[:name]}
                type="text"
                label="Название"
                placeholder="Верстак"
                class="crf-paper-input"
              />
              <button
                id="craft-create-workshop"
                type="submit"
                class="crf-do crf-do--ready"
              >
                Оборудовать
              </button>
            </.form>
          </section>

          <section
            :if={@workspace && not @workspace_here?}
            id="craft-workshop-away"
            class="crf-ledger crf-ledger--warning"
          >
            <p class="crf-ledger__eyebrow">пометка на полях</p>
            <p class="crf-ledger__copy">
              Ваш активный верстак находится в другом месте. Вернитесь к нему, чтобы начать работу.
            </p>
          </section>

          <section
            :if={@workspace_here?}
            id="craft-start"
            class="crf-work-order"
          >
            <span class="crf-work-order__clip" aria-hidden="true"></span>
            <div class="crf-work-order__head">
              <div>
                <p class="crf-ledger__eyebrow">заказ на изготовление</p>
                <h2 class="crf-ledger__title">Положить чертёж на верстак</h2>
              </div>
              <span class="crf-work-order__stamp">кузница</span>
            </div>
            <p :if={@recipes == []} id="craft-recipes-empty" class="crf-ledger__copy">
              Для этого мира ещё не записаны чертежи.
            </p>
            <.form
              :if={@recipes != []}
              for={@craft_form}
              id="craft-form"
              phx-submit="craft"
              class="crf-order-form"
            >
              <.input
                field={@craft_form[:recipe_id]}
                type="select"
                label="Чертёж"
                prompt="Выберите чертёж"
                options={@recipe_options}
                class="crf-paper-input"
              />
              <.input
                field={@craft_form[:quantity]}
                type="number"
                label="Количество"
                min="1"
                inputmode="numeric"
                class="crf-paper-input"
              />
              <button
                id="craft-start-job"
                type="submit"
                class="crf-do crf-do--ready"
              >
                В огонь
              </button>
            </.form>
          </section>

          <section id="craft-jobs" class="crf-job-board">
            <div class="crf-job-board__head">
              <div>
                <p class="crf-label">Доска заказов</p>
                <h2 class="crf-job-board__title">Работы</h2>
              </div>
              <span class="crf-job-board__nail" aria-hidden="true"></span>
            </div>
            <p :if={@jobs == []} id="craft-jobs-empty" class="crf-hint">
              Нет активных или завершённых работ.
            </p>
            <article
              :for={job <- @jobs}
              id={"craft-job-#{job.id}"}
              class="crf-job-ticket"
            >
              <div class="crf-job-ticket__copy">
                <p class="crf-job-ticket__name">{job.recipe.name} ×{job.quantity}</p>
                <p class="crf-job-ticket__meta">
                  {job_status_label(job.status)} · готовность {format_time(job.completes_at)}
                </p>
              </div>
              <button
                :if={job.status == :active}
                id={"craft-collect-#{job.id}"}
                type="button"
                phx-click="collect"
                phx-value-job-id={job.id}
                class="crf-job-ticket__collect"
              >
                Проверить готовность
              </button>
            </article>
          </section>

          <button
            id="craft-refresh"
            type="button"
            phx-click="refresh"
            class="crf-refresh"
          >
            ↻ проверить угли и заказы
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
  defp format_time(nil), do: "ожидает расчёта"
  defp format_time(time), do: Calendar.strftime(time, "%d.%m %H:%M UTC")

  defp tool_code_label("demo_travel_ration"), do: "Дорожный паёк"
  defp tool_code_label("demo_lumen_dust"), do: "Световая пыль"
  defp tool_code_label("construction_material"), do: "Строевой камень"
  defp tool_code_label("forge"), do: "Горн"
  defp tool_code_label("anvil"), do: "Наковальня"
  defp tool_code_label("hammer"), do: "Молот"
  defp tool_code_label("workbench"), do: "Верстак"
  defp tool_code_label(_code), do: "Неопознанный инструмент"

  defp job_status_label(:active), do: "в работе"
  defp job_status_label(:completed), do: "готово"
  defp job_status_label(:claimed), do: "получено"
  defp job_status_label(:failed), do: "сорвано"
  defp job_status_label(_status), do: "состояние уточняется"

  defp error_message(:active_base_not_found), do: "Верстак доступен только на активной базе."
  defp error_message(:crafting_workshop_exists), do: "У вас уже есть активный верстак."
  defp error_message(:crafting_workshop_not_here), do: "Этот верстак находится в другом месте."
  defp error_message(:craft_recipe_not_found), do: "Чертёж больше недоступен."
  defp error_message(:craft_job_not_found), do: "Работа больше недоступна."
  defp error_message(:invalid_quantity), do: "Укажите положительное количество."

  defp error_message(_reason),
    do: "Команда не выполнена: проверьте специализацию, инструменты и материалы."
end
