defmodule MMGOWeb.RealmsLive do
  @moduledoc """
  Read-only realm directory and scoped migration history.
  """
  use MMGOWeb, :live_view

  alias MMGO.{Federation, Play}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Миры")
     |> assign(:error, nil)
     |> refresh_directory()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_directory(socket)}

  @impl true
  def handle_event(
        "start_migration",
        %{"migration" => %{"destination_id" => destination_id, "amount" => amount}},
        socket
      ) do
    with {:ok, amount} <- parse_positive_amount(amount),
         {:ok, result} <-
           Play.start_scoped_remote_migration(
             socket.assigns.current_scope.character,
             destination_id,
             amount
           ) do
      message =
        if result.remote_import_pending? do
          "Переход зафиксирован, но удалённый мир ещё не подтвердил прибытие. Ваше место в очереди сохранено; повторите подтверждение ниже."
        else
          "Переход подтверждён удалённым миром. Исходный персонаж заморожен до конца перехода."
        end

      {:noreply,
       socket
       |> put_flash(:info, message)
       |> assign(:error, nil)
       |> refresh_directory()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("retry_migration", %{"migration-id" => migration_id}, socket) do
    case Play.retry_scoped_remote_migration(socket.assigns.current_scope.character, migration_id) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Удалённый мир подтвердил сохранённый переход.")
         |> assign(:error, nil)
         |> refresh_directory()}

      {:error, reason} ->
        {:noreply,
         assign(
           socket,
           :error,
           "Подтверждение пока не получено. Переход остаётся сохранённым: #{error_message(reason)}"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="realms-screen" class="realm-scene">
        <div class="realm-atlas">
          <div class="realm-tools">
            <.link
              :if={@state.character.status == :active}
              id="realms-back-map"
              navigate={~p"/map"}
              class="realm-exit"
            >
              ← Карта мира
            </.link>
            <button
              id="realms-refresh"
              type="button"
              phx-click="refresh"
              class="realm-tool"
            >
              Обновить каталог
            </button>
          </div>

          <header class="realm-cover">
            <p class="text-xs uppercase tracking-[0.25em] text-indigo-200/75">федеральный атлас</p>
            <h1 class="mt-2 font-serif text-3xl text-indigo-100">Миры и переходы</h1>
            <p class="mt-3 max-w-3xl text-sm leading-6 text-stone-300">
              Каталог показывает последнюю подтверждённую манифестацию каждого мира. Переход создаёт новое прибытие, конвертирует валюту и удерживает исходного персонажа на время заморозки. Инвентарь и владение остаются в исходном мире, а библиотека заклинаний не переносится.
            </p>
          </header>

          <div
            :if={@error}
            id="realms-error"
            class="realm-slip realm-slip--error"
          >
            {@error}
          </div>

          <section
            id="realms-current"
            class="realm-passport"
          >
            <p class="text-xs uppercase tracking-[0.2em] text-sky-200/75">ваш текущий мир</p>
            <div class="mt-2 flex flex-wrap items-baseline justify-between gap-3">
              <h2 class="font-serif text-2xl text-sky-100">{@state.current_realm.name}</h2>
              <span class="font-mono text-xs text-stone-500">{@state.current_realm.slug}</span>
            </div>
            <p class="mt-3 text-sm text-stone-300">
              Валюта: {@state.current_realm.currency_code} · правила магии: {magic_scope_label(
                @state.current_realm.ruleset
              )}
            </p>
          </section>

          <section
            :if={@state.active_migration}
            id="realms-active-migration"
            class="realm-passport realm-passport--active"
          >
            <p class="text-xs uppercase tracking-[0.2em] text-amber-200/75">активный переход</p>
            <h2 class="mt-2 font-serif text-2xl text-amber-100">
              {migration_destination_label(@state.active_migration)}
            </h2>
            <dl class="mt-4 grid gap-3 text-sm sm:grid-cols-2">
              <div>
                <dt class="text-stone-500">Переведено</dt>
                <dd id="realms-migration-currency" class="mt-1 text-stone-100">
                  {@state.active_migration.currency_amount} → {@state.active_migration.converted_currency_amount}
                </dd>
              </div>
              <div>
                <dt class="text-stone-500">Исходная заморозка до</dt>
                <dd id="realms-migration-freeze-ends" class="mt-1 text-stone-100">
                  {format_time(@state.active_migration.freeze_ends_at)}
                </dd>
              </div>
              <div>
                <dt class="text-stone-500">Уровень при прибытии</dt>
                <dd class="mt-1 text-stone-100">{@state.active_migration.destination_level}</dd>
              </div>
              <div>
                <dt class="text-stone-500">Опыт при прибытии</dt>
                <dd class="mt-1 text-stone-100">{@state.active_migration.destination_xp}</dd>
              </div>
            </dl>

            <%= if remote_migration?(@state.active_migration) do %>
              <p
                id="realms-remote-import-status"
                class="mt-4 text-sm leading-6 text-stone-300"
              >
                {remote_import_copy(@state.active_migration)}
              </p>
              <button
                :if={remote_import_pending?(@state.active_migration)}
                id="realms-retry-migration"
                type="button"
                phx-click="retry_migration"
                phx-value-migration-id={@state.active_migration.id}
                class="realm-seal-action"
              >
                Повторить подтверждение прибытия
              </button>
            <% end %>
          </section>

          <section
            id="realms-directory"
            class="realm-pages"
          >
            <div class="flex flex-wrap items-end justify-between gap-3">
              <div>
                <p class="text-xs uppercase tracking-[0.2em] text-stone-500">доступные манифесты</p>
                <h2 class="mt-1 font-serif text-2xl text-stone-100">Другие миры</h2>
              </div>
              <span class="text-sm text-stone-400">
                {@state.remote_realms |> length()} в каталоге
              </span>
            </div>

            <p
              :if={@state.remote_realms == []}
              id="realms-empty"
              class="realm-note"
            >
              В каталоге нет активных удалённых манифестов.
            </p>

            <ul :if={@state.remote_realms != []} class="realm-manifest-grid">
              <li
                :for={realm <- @state.remote_realms}
                id={"remote-realm-#{realm.id}"}
                class="realm-manifest"
              >
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <h3 class="font-serif text-xl text-stone-100">{realm.name}</h3>
                    <p class="mt-1 font-mono text-xs text-stone-500">{realm.slug}</p>
                  </div>
                  <span class={migration_badge_class(realm.allow_migration)}>
                    {migration_label(realm.allow_migration)}
                  </span>
                </div>
                <p class="mt-4 min-h-10 text-sm leading-6 text-stone-300">
                  {realm.public_description || "Описание от оператора пока не опубликовано."}
                </p>
                <dl class="mt-4 grid gap-3 text-sm sm:grid-cols-2">
                  <div>
                    <dt class="text-stone-500">Оператор</dt>
                    <dd class="mt-1 text-stone-200">{realm.operator_name || "не указан"}</dd>
                  </div>
                  <div>
                    <dt class="text-stone-500">Население (манифест)</dt>
                    <dd class="mt-1 text-stone-200">{realm.population_hint}</dd>
                  </div>
                  <div>
                    <dt class="text-stone-500">Валюта</dt>
                    <dd class="mt-1 text-stone-200">{realm.currency_code}</dd>
                  </div>
                  <div>
                    <dt class="text-stone-500">Последняя синхронизация</dt>
                    <dd class="mt-1 text-stone-200">{format_time(realm.last_synced_at)}</dd>
                  </div>
                </dl>
                <p class="mt-4 text-xs text-stone-500">
                  Вход: {realm.entry_location_slug || "не объявлен"} · правила магии: {magic_scope_label(
                    realm.ruleset
                  )}
                </p>
                <.form
                  :if={
                    @state.can_start_remote_migration? &&
                      realm.id in @state.remote_migration_ready_ids
                  }
                  for={@migration_form}
                  id={"realms-start-migration-#{realm.id}"}
                  phx-submit="start_migration"
                  class="realm-transfer"
                >
                  <.input
                    id={"realms-migration-destination-#{realm.id}"}
                    field={@migration_form[:destination_id]}
                    type="hidden"
                    value={realm.id}
                  />
                  <.input
                    id={"realms-migration-amount-#{realm.id}"}
                    field={@migration_form[:amount]}
                    type="number"
                    label={"Сумма из кошелька (доступно #{@state.currency_balance})"}
                    min="1"
                    max={@state.currency_balance}
                    required
                  />
                  <button
                    id={"realms-start-migration-submit-#{realm.id}"}
                    type="submit"
                    class="realm-transfer__seal"
                  >
                    Начать переход
                  </button>
                </.form>
                <p
                  :if={realm.allow_migration && realm.id not in @state.remote_migration_ready_ids}
                  id={"realms-migration-unavailable-#{realm.id}"}
                  class="realm-manifest__warning"
                >
                  Мир объявил переходы, но защищённый канал прибытия ещё не настроен оператором.
                </p>
              </li>
            </ul>
          </section>

          <section
            id="realm-migration-history"
            class="realm-history"
          >
            <p class="text-xs uppercase tracking-[0.2em] text-stone-500">ваша история переходов</p>
            <p
              :if={@state.migrations == []}
              id="realm-migrations-empty"
              class="mt-4 text-sm text-stone-400"
            >
              Ваша учётная запись ещё не совершала переходов между мирами.
            </p>
            <ul :if={@state.migrations != []} class="mt-4 space-y-2">
              <li
                :for={migration <- @state.migrations}
                id={"realm-migration-#{migration.id}"}
                class="realm-history__entry"
              >
                <span>
                  {migration_origin_label(migration)} → {migration_destination_label(migration)}
                </span>
                <span class="text-stone-400">{migration_status_label(migration.status)}</span>
              </li>
            </ul>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp refresh_directory(socket) do
    case Play.realm_directory_state(socket.assigns.current_scope.character) do
      {:ok, state} ->
        socket
        |> assign(:state, state)
        |> assign(:error, nil)
        |> assign(
          :migration_form,
          to_form(%{"destination_id" => "", "amount" => ""}, as: :migration)
        )

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Не удалось открыть атлас миров.")
        |> push_navigate(to: ~p"/map")
    end
  end

  defp migration_label(true), do: "переходы заявлены"
  defp migration_label(false), do: "переходы закрыты"

  defp migration_badge_class(true),
    do: "realm-seal realm-seal--open"

  defp migration_badge_class(false),
    do: "realm-seal realm-seal--closed"

  defp magic_scope_label(ruleset) when is_map(ruleset) do
    case Map.get(ruleset, "magic_scope") do
      "global" -> "везде"
      "tower_and_dungeon" -> "Башня и подземелье"
      _other -> "не объявлены"
    end
  end

  defp magic_scope_label(_ruleset), do: "не объявлены"

  defp migration_origin_label(%{origin_realm: %{name: name}}), do: name
  defp migration_origin_label(_migration), do: "исходный мир"

  defp migration_destination_label(%{destination_realm: %{name: name}}), do: name
  defp migration_destination_label(%{remote_realm: %{name: name}}), do: name
  defp migration_destination_label(_migration), do: "неизвестный мир"

  defp migration_status_label(:active), do: "в пути"
  defp migration_status_label(:completed), do: "завершён"
  defp migration_status_label(:cancelled), do: "отменён"
  defp migration_status_label(_status), do: "неизвестно"

  defp remote_migration?(%{mode: :remote}), do: true
  defp remote_migration?(_migration), do: false

  defp remote_import_pending?(migration),
    do: Federation.remote_import_status(migration) == :pending

  defp remote_import_copy(migration) do
    case Federation.remote_import_status(migration) do
      :accepted ->
        "Удалённый мир подтвердил новое прибытие. Исходный персонаж останется заморожен до указанного срока и получит пассивный опыт."

      :pending ->
        "Удалённый мир ещё не подтвердил прибытие. Запрос и ссылка перехода сохранены сервером; повторная попытка использует тот же безопасный идентификатор."

      _other ->
        "Статус удалённого прибытия уточняется."
    end
  end

  defp parse_positive_amount(value) when is_binary(value) do
    case Integer.parse(value) do
      {amount, ""} when amount > 0 -> {:ok, amount}
      _other -> {:error, :invalid_migration_amount}
    end
  end

  defp parse_positive_amount(_value), do: {:error, :invalid_migration_amount}

  defp error_message(:invalid_migration_amount),
    do: "Укажите положительную сумму для конвертации."

  defp error_message(:remote_realm_not_found), do: "Этот мир больше не доступен для перехода."
  defp error_message(:realm_migration_not_found), do: "Переход не принадлежит текущему персонажу."

  defp error_message(%Ecto.Changeset{}),
    do: "Сервер не разрешил переход: проверьте баланс и условия мира."

  defp error_message(_reason), do: "Переход пока недоступен."

  defp format_time(%DateTime{} = time), do: Calendar.strftime(time, "%d.%m · %H:%M UTC")
  defp format_time(_time), do: "нет отметки"
end
