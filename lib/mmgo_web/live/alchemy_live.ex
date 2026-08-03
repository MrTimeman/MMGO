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
      <main id="alchemy-screen" class="game-screen alc-screen">
        <div class="alc-root">
          <.link id="alchemy-back-to-base" navigate={~p"/base"} class="alc-exit">
            ← вернуться на базу
          </.link>

          <div
            :if={@error}
            id="alchemy-error"
            class="alc-alert alc-alert--error"
          >
            {@error}
          </div>

          <section
            id="alchemy-workshop-scene"
            class="alc-workshop-scene"
            aria-label="Алхимическая мастерская"
          >
            <div class="alc-workshop-scene__room" aria-hidden="true">
              <div class="alc-window">
                <span class="alc-window__bar alc-window__bar--vertical"></span>
                <span class="alc-window__bar alc-window__bar--horizontal"></span>
              </div>

              <div class="alc-cabinet">
                <span class="alc-cabinet__shelf alc-cabinet__shelf--upper"></span>
                <span class="alc-cabinet__shelf alc-cabinet__shelf--lower"></span>
                <span class="alc-bottle alc-bottle--one"></span>
                <span class="alc-bottle alc-bottle--two"></span>
                <span class="alc-bottle alc-bottle--three"></span>
                <span class="alc-bottle alc-bottle--four"></span>
                <span class="alc-bottle alc-bottle--five"></span>
              </div>

              <div class="alc-workbench"></div>
              <div class="alc-mortar">
                <span class="alc-mortar__bowl"></span>
                <span class="alc-mortar__pestle"></span>
              </div>

              <div class={[
                "alc-vessel",
                @ingredients != [] && "alc-vessel--live",
                @workspace_here? && "alc-vessel--ready"
              ]}>
                <div class="alc-vessel__neck"></div>
                <div class="alc-vessel__flask">
                  <div class="alc-vessel__brew" style="--fill:54%">
                    <span class="alc-bubble alc-bubble--1"></span>
                    <span class="alc-bubble alc-bubble--2"></span>
                    <span class="alc-bubble alc-bubble--3"></span>
                  </div>
                  <span class="alc-vessel__shine"></span>
                </div>
                <span class="alc-vessel__flame"></span>
              </div>
            </div>
          </section>

          <header class="alc-head">
            <p class="alc-kicker">алхимия · {@base.name}</p>
            <h1 class="alc-title">
              {if @workspace, do: @workspace.name, else: "Алхимический стол"}
            </h1>
            <p class="alc-sub">
              Стекло, жар и свойства мира. Здесь ингредиенты становятся рецептом.
            </p>
          </header>

          <section class="alc-tools" aria-labelledby="alchemy-tools-title">
            <p id="alchemy-tools-title" class="alc-label">Инструменты на столе</p>
            <div class="alc-tools__row">
              <span
                :if={@installed_tool_codes == []}
                class="alc-tool alc-tool--missing"
              >
                <span class="alc-tool__mark">×</span> пока пусто
              </span>
              <span
                :for={code <- @installed_tool_codes}
                class="alc-tool alc-tool--owned"
              >
                <span class="alc-tool__mark">✓</span>
                {tool_code_label(code)}
              </span>
            </div>
          </section>

          <section
            :if={is_nil(@workspace)}
            id="alchemy-workshop-setup"
            class="alc-ledger alc-ledger--setup"
          >
            <span class="alc-ledger__wax" aria-hidden="true">A</span>
            <p class="alc-ledger__eyebrow">страница лаборатории</p>
            <h2 class="alc-ledger__title">Оборудовать стол</h2>
            <p class="alc-ledger__copy">
              Назовите лабораторию. Инструменты отмечаются только по вашей настоящей котомке.
            </p>
            <.form
              for={@workshop_form}
              id="alchemy-workshop-form"
              phx-submit="create_workshop"
              class="alc-setup-form"
            >
              <.input
                field={@workshop_form[:name]}
                type="text"
                label="Название"
                placeholder="Алхимический стол"
                class="alc-paper-input"
              />
              <button
                id="alchemy-create-workshop"
                type="submit"
                class="alc-brew alc-brew--ready"
              >
                Оборудовать
              </button>
            </.form>
          </section>

          <section
            :if={@workspace && not @workspace_here?}
            id="alchemy-workshop-away"
            class="alc-ledger alc-ledger--warning"
          >
            <p class="alc-ledger__eyebrow">пометка на полях</p>
            <p class="alc-ledger__copy">
              Ваш активный стол находится в другом месте. Вернитесь к нему, чтобы начать новую варку.
            </p>
          </section>

          <section
            :if={@workspace_here?}
            id="alchemy-brew"
            class="alc-recipe-desk"
          >
            <span class="alc-recipe-desk__bookmark" aria-hidden="true"></span>
            <div class="alc-recipe-desk__head">
              <div>
                <p class="alc-ledger__eyebrow">новая запись</p>
                <h2 class="alc-ledger__title">Начать варку</h2>
              </div>
              <span class="alc-recipe-desk__folio">до 6 реагентов</span>
            </div>
            <p class="alc-ledger__copy">
              Отмерьте ингредиенты. Мир истолкует только их неизменные примитивы,
              а движок не пропустит новое или слишком сильное состояние.
            </p>
            <p
              :if={@ingredients == []}
              id="alchemy-ingredients-empty"
              class="alc-ledger__copy alc-ledger__copy--empty"
            >
              В котомке нет ингредиентов с алхимическими примитивами.
            </p>
            <.form
              :if={@ingredients != []}
              for={@brew_form}
              id="alchemy-brew-form"
              phx-submit="brew"
              class="alc-brew-form"
            >
              <div id="alchemy-ingredient-list" class="alc-strip">
                <div
                  :for={item <- @ingredients}
                  id={"alchemy-ingredient-#{item.id}"}
                  class="alc-ing alc-ing--inventory"
                >
                  <span class="alc-ing__stopper" aria-hidden="true"></span>
                  <span class="alc-ing__glyph">❧</span>
                  <p class="alc-ing__name">{item.item_template.name}</p>
                  <p class="alc-ing__stock">
                    доступно {item.quantity - item.reserved_quantity}
                  </p>
                  <p class="alc-ing__note">{primitive_list(item.item_template.metadata)}</p>
                  <.input
                    id={"alchemy-ingredient-quantity-#{item.id}"}
                    name={"brew[ingredients][#{item.id}]"}
                    value="0"
                    type="number"
                    label="В котёл"
                    min="0"
                    max={item.quantity - item.reserved_quantity}
                    inputmode="numeric"
                    class="alc-quantity"
                  />
                </div>
              </div>
              <button
                id="alchemy-start-brew"
                type="submit"
                class="alc-brew alc-brew--ready"
              >
                Истолковать и поставить
              </button>
            </.form>
          </section>

          <section id="alchemy-jobs" class="alc-job-ledger">
            <div class="alc-job-ledger__head">
              <div>
                <p class="alc-label">Лабораторный журнал</p>
                <h2 class="alc-job-ledger__title">Варки</h2>
              </div>
              <span class="alc-job-ledger__flourish" aria-hidden="true">❦</span>
            </div>
            <p :if={@jobs == []} id="alchemy-jobs-empty" class="alc-hint">
              Нет активных или завершённых варок.
            </p>
            <article
              :for={job <- @jobs}
              id={"alchemy-job-#{job.id}"}
              class="alc-job-slip"
            >
              <div class="alc-job-slip__copy">
                <p class="alc-job-slip__name">{job.recipe.name} ×{job.quantity}</p>
                <p class="alc-job-slip__meta">
                  {job_status_label(job.status)} · готовность {format_time(job.completes_at)}
                </p>
              </div>
              <button
                :if={job.status == :active}
                id={"alchemy-collect-#{job.id}"}
                type="button"
                phx-click="collect"
                phx-value-job-id={job.id}
                class="alc-job-slip__collect"
              >
                Проверить готовность
              </button>
            </article>
          </section>

          <button
            id="alchemy-refresh"
            type="button"
            phx-click="refresh"
            class="alc-refresh"
          >
            ↻ свериться с лабораторным журналом
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

  defp primitive_list(metadata) do
    metadata
    |> Map.get("alchemical_primitives", %{})
    |> Enum.sort_by(fn {primitive, _amount} -> primitive end)
    |> Enum.map_join(" · ", fn {primitive, amount} ->
      "#{primitive_label(primitive)} #{amount}"
    end)
  end

  defp format_time(nil), do: "ожидает расчёта"
  defp format_time(time), do: Calendar.strftime(time, "%d.%m %H:%M UTC")

  defp tool_code_label("demo_travel_ration"), do: "Дорожный паёк"
  defp tool_code_label("demo_lumen_dust"), do: "Световая пыль"
  defp tool_code_label("construction_material"), do: "Строевой камень"
  defp tool_code_label("cauldron"), do: "Котёл"
  defp tool_code_label("mortar"), do: "Ступка"
  defp tool_code_label("alembic"), do: "Перегонный куб"
  defp tool_code_label(_code), do: "Неопознанный инструмент"

  defp job_status_label(:active), do: "варится"
  defp job_status_label(:completed), do: "готово"
  defp job_status_label(:claimed), do: "получено"
  defp job_status_label(:failed), do: "испорчено"
  defp job_status_label(_status), do: "состояние уточняется"

  defp primitive_label("heat"), do: "жар"
  defp primitive_label("cold"), do: "холод"
  defp primitive_label("water"), do: "вода"
  defp primitive_label("earth"), do: "земля"
  defp primitive_label("air"), do: "воздух"
  defp primitive_label("toxicity"), do: "ядовитость"
  defp primitive_label("binding"), do: "связывание"
  defp primitive_label("restoration"), do: "восстановление"
  defp primitive_label("life"), do: "жизнь"
  defp primitive_label("death"), do: "смерть"
  defp primitive_label("volatility"), do: "нестабильность"
  defp primitive_label("clarity"), do: "ясность"
  defp primitive_label(_primitive), do: "неизвестное свойство"

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
