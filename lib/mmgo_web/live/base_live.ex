defmodule MMGOWeb.BaseLive do
  @moduledoc """
  Scoped base, storage, and construction surface.

  Every transfer is reconstructed from `MMGO.Play` and the current location;
  this LiveView never receives a base owner or arbitrary storage authority from
  the browser.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_base(socket, socket.assigns.current_scope.character, params["id"])}
  end

  @impl true
  def handle_event("establish", %{"base_establish" => attrs}, socket) do
    case Play.establish_current_base(socket.assigns.character, attrs) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Владение оформлено. Строительство, если нужно, идёт по игровому времени."
         )
         |> refresh_base()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("deposit", %{"base_deposit" => params}, socket) do
    with {:ok, quantity} <- parse_quantity(params["quantity"]),
         {:ok, _state} <-
           Play.deposit_to_current_base(
             socket.assigns.character,
             params["inventory_item_id"],
             quantity,
             socket.assigns.selected_base_id
           ) do
      {:noreply,
       socket |> put_flash(:info, "Предмет перенесён в защищённое хранилище.") |> refresh_base()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("withdraw", %{"base_withdraw" => params}, socket) do
    with {:ok, quantity} <- parse_quantity(params["quantity"]),
         {:ok, _state} <-
           Play.withdraw_from_current_base(
             socket.assigns.character,
             params["storage_item_id"],
             quantity,
             socket.assigns.selected_base_id
           ) do
      {:noreply, socket |> put_flash(:info, "Предмет взят из хранилища.") |> refresh_base()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("rest", _params, socket) do
    case Play.rest_at_current_base(socket.assigns.character, socket.assigns.selected_base_id) do
      {:ok, _state} ->
        {:noreply,
         socket
         |> put_flash(:info, "Вы поели из запасов и восстановились в защищённом владении.")
         |> refresh_base()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("configure_organization_ownership", %{"base_ownership" => params}, socket) do
    with {:ok, share_bps} <- parse_share_bps(params["share_bps"]),
         {:ok, _state} <-
           Play.configure_current_base_organization_share(
             socket.assigns.character,
             socket.assigns.selected_base_id,
             params["organization_id"],
             share_bps
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Доля и доступ организации к этой базе обновлены.")
       |> refresh_base()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_base(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="base-screen" class="game-root min-h-full px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-5">
          <.link id="base-back-to-map" navigate={~p"/map"} class="map-back-link">← Карта мира</.link>

          <header class="rounded-xl border border-amber-500/25 bg-stone-900/80 p-6 shadow-xl">
            <p class="text-xs uppercase tracking-[0.22em] text-amber-300/70">
              владение · {@location.name}
            </p>
            <h1 class="mt-2 font-serif text-3xl text-amber-100">База и хранилище</h1>
            <p id="base-carry-summary" class="mt-3 text-sm text-stone-400">
              {@character.name} · поклажа {Map.get(@survival, :carried_weight, 0)} / {Map.get(
                @survival,
                :carry_capacity,
                0
              )}
            </p>
          </header>

          <div
            :if={@error}
            id="base-error"
            class="rounded-md border border-red-500/50 bg-red-950/30 px-4 py-3 text-sm text-red-200"
          >
            {@error}
          </div>

          <section
            :if={@requires_base_selection?}
            id="base-accessible-choices"
            class="rounded-xl border border-cyan-400/30 bg-cyan-950/15 p-6"
          >
            <p class="text-xs uppercase tracking-[0.2em] text-cyan-200/75">общие ключи</p>
            <h2 class="mt-1 font-serif text-2xl text-cyan-100">Выберите доступную базу</h2>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              В этой точке доступно несколько общих владений. База выбирается явно, а право на
              каждую операцию будет заново проверено на стороне мира.
            </p>
            <div class="mt-4 grid gap-2 sm:grid-cols-2">
              <.link
                :for={base <- @active_base_choices}
                id={"base-select-#{base.id}"}
                navigate={~p"/base/#{base.id}"}
                class="rounded-lg border border-cyan-300/30 bg-stone-950/35 px-4 py-3 text-sm text-cyan-50 transition hover:border-cyan-200/70 hover:bg-cyan-300/10"
              >
                <span class="block font-semibold">{base.name}</span>
                <span class="mt-1 block text-xs text-cyan-100/70">
                  {if base.direct_owner?, do: "личное владение", else: "общий доступ организации"} ·
                  вместимость {base.storage_capacity}
                </span>
              </.link>
            </div>
          </section>

          <section
            :if={@active_base}
            id="base-active"
            class="rounded-xl border border-emerald-500/25 bg-emerald-950/15 p-6"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p class="text-xs uppercase tracking-[0.18em] text-emerald-300/70">
                  защищённое владение
                </p>
                <h2 class="mt-1 font-serif text-2xl text-emerald-100">{@active_base.name}</h2>
                <p class="mt-2 text-sm text-stone-400">
                  Вещи внутри нельзя отнять; использовать их можно только вернувшись сюда.
                </p>
              </div>
              <span
                id="base-storage-capacity"
                class="rounded-full border border-emerald-400/30 px-3 py-1 text-sm text-emerald-100"
              >
                {@storage_weight} / {@storage_capacity} веса
              </span>
            </div>

            <section
              id="base-ownership"
              class="mt-6 rounded-xl border border-amber-400/20 bg-amber-950/15 p-5"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-amber-200/75">доли и ключи</p>
              <h3 class="mt-1 font-serif text-xl text-amber-100">Совместное владение</h3>
              <p
                :if={@ownership.via_organization?}
                id="base-access-via-organization"
                class="mt-2 rounded-md border border-cyan-300/25 bg-cyan-950/20 px-3 py-2 text-sm leading-6 text-cyan-100"
              >
                Вы здесь как хранитель организации. Вклад и выдача предметов, а также отдых,
                происходят из общих запасов этой базы.
              </p>
              <p class="mt-2 text-sm leading-6 text-stone-300">
                Титульному владельцу принадлежит {@ownership.owner_share_bps} из 10 000 долей.
                Положительная доля организации открывает реальные ключи от склада только её
                действующим казначеям.
              </p>
              <ul id="base-organization-shares" class="mt-3 space-y-2 text-sm text-stone-200">
                <li
                  :for={share <- @ownership.organization_shares}
                  id={"base-organization-share-#{share.organization_id}"}
                  class="flex flex-wrap items-center justify-between gap-2 rounded bg-stone-950/35 px-3 py-2"
                >
                  <span>{share.organization_name}</span>
                  <span class="text-amber-100">
                    {share.share_bps} / 10 000 {if share.active?, do: "долей", else: "долей · архив"}
                  </span>
                </li>
                <li
                  :if={@ownership.organization_shares == []}
                  id="base-organization-shares-empty"
                  class="rounded bg-stone-950/35 px-3 py-2 text-stone-400"
                >
                  У этой базы пока нет организации-сособственника.
                </li>
              </ul>

              <.form
                :if={@ownership.is_owner? and @ownership_options != []}
                for={@ownership_form}
                id="base-organization-ownership-form"
                phx-submit="configure_organization_ownership"
                class="mt-5 grid gap-3 md:grid-cols-[1fr_11rem_auto] md:items-end"
              >
                <.input
                  field={@ownership_form[:organization_id]}
                  type="select"
                  label="Организация"
                  prompt="Выберите организацию"
                  options={@ownership_options}
                />
                <.input
                  field={@ownership_form[:share_bps]}
                  type="number"
                  label="Доля (0–9999)"
                  min="0"
                  max="9999"
                  inputmode="numeric"
                />
                <button
                  id="base-organization-ownership-submit"
                  type="submit"
                  class="mb-4 rounded-md border border-amber-300/60 px-4 py-3 text-sm font-semibold text-amber-100 transition hover:bg-amber-300/10"
                >
                  Обновить долю
                </button>
              </.form>
              <p
                :if={@ownership.is_owner? and @ownership_options == []}
                id="base-organization-ownership-unavailable"
                class="mt-4 text-sm text-stone-400"
              >
                Чтобы выдать долю, сначала станьте казначеем подходящей организации.
              </p>
            </section>

            <div class="mt-6 grid gap-5 lg:grid-cols-2">
              <section>
                <h3 class="font-serif text-lg text-stone-100">Внести из котомки</h3>
                <p
                  :if={@carried_items == []}
                  id="base-carried-empty"
                  class="mt-2 text-sm text-stone-400"
                >
                  В котомке нет предметов для хранения.
                </p>
                <.form
                  :if={@carried_items != []}
                  for={@deposit_form}
                  id="base-deposit-form"
                  phx-submit="deposit"
                  class="mt-3 space-y-1"
                >
                  <.input
                    field={@deposit_form[:inventory_item_id]}
                    type="select"
                    label="Предмет"
                    prompt="Выберите предмет"
                    options={@carried_options}
                  />
                  <.input
                    field={@deposit_form[:quantity]}
                    type="number"
                    label="Количество"
                    min="1"
                    inputmode="numeric"
                  />
                  <button
                    id="base-deposit"
                    type="submit"
                    class="rounded-md bg-emerald-300 px-4 py-2 font-semibold text-stone-950 transition hover:bg-emerald-200"
                  >
                    В хранилище
                  </button>
                </.form>
              </section>

              <section>
                <h3 class="font-serif text-lg text-stone-100">Взять с полки</h3>
                <p
                  :if={@storage_items == []}
                  id="base-storage-empty"
                  class="mt-2 text-sm text-stone-400"
                >
                  Хранилище пока пусто.
                </p>
                <.form
                  :if={@storage_items != []}
                  for={@withdraw_form}
                  id="base-withdraw-form"
                  phx-submit="withdraw"
                  class="mt-3 space-y-1"
                >
                  <.input
                    field={@withdraw_form[:storage_item_id]}
                    type="select"
                    label="Предмет"
                    prompt="Выберите предмет"
                    options={@storage_options}
                  />
                  <.input
                    field={@withdraw_form[:quantity]}
                    type="number"
                    label="Количество"
                    min="1"
                    inputmode="numeric"
                  />
                  <button
                    id="base-withdraw"
                    type="submit"
                    class="rounded-md border border-emerald-300/60 px-4 py-2 font-semibold text-emerald-100 transition hover:bg-emerald-300/10"
                  >
                    В котомку
                  </button>
                </.form>
              </section>
            </div>

            <div class="mt-6 grid gap-4 md:grid-cols-2">
              <section>
                <h3 class="font-serif text-lg text-stone-100">Котомка</h3>
                <ul id="base-carried-items" class="mt-2 space-y-2 text-sm text-stone-300">
                  <li
                    :for={item <- @carried_items}
                    id={"base-carried-#{item.id}"}
                    class="flex justify-between rounded bg-stone-950/35 px-3 py-2"
                  >
                    <span>{item.item_template.name}</span><span>×{item.quantity}</span>
                  </li>
                </ul>
              </section>
              <section>
                <h3 class="font-serif text-lg text-stone-100">Хранилище</h3>
                <ul id="base-storage-items" class="mt-2 space-y-2 text-sm text-stone-300">
                  <li
                    :for={item <- @storage_items}
                    id={"base-storage-#{item.id}"}
                    class="flex justify-between rounded bg-stone-950/35 px-3 py-2"
                  >
                    <span>{item.item_template.name}</span><span>×{item.quantity}</span>
                  </li>
                </ul>
              </section>
            </div>

            <section
              id="base-rest"
              class="mt-6 rounded-xl border border-sky-400/20 bg-sky-950/15 p-5"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-sky-200/75">восстановление</p>
              <h3 class="mt-1 font-serif text-xl text-sky-100">Отдых у своих запасов</h3>
              <p id="base-rest-state" class="mt-2 text-sm leading-6 text-stone-300">
                <%= cond do %>
                  <% @can_rest? -> %>
                    Голод и дорожный урон можно снять: отдых съест одну порцию провизии из хранилища.
                  <% @survival.recovered? -> %>
                    Силы уже восстановлены; следующая дорога снова будет рассчитываться по реальным запасам.
                  <% @survival.starving? or @survival.health_drain > 0 -> %>
                    Для восстановления положите в хранилище съедобную провизию.
                  <% true -> %>
                    Сейчас нет голодных последствий, которые нужно снимать отдыхом.
                <% end %>
              </p>
              <button
                :if={@can_rest?}
                id="base-rest-submit"
                type="button"
                phx-click="rest"
                class="mt-4 rounded-md bg-sky-300 px-4 py-2 text-sm font-semibold text-stone-950 transition hover:bg-sky-200"
              >
                Поесть и отдохнуть
              </button>
            </section>

            <section
              :if={not @ownership.via_organization?}
              id="base-workbench"
              class="mt-6 rounded-xl border border-violet-400/20 bg-violet-950/15 p-5"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-violet-200/75">рабочее место</p>
              <h3 class="mt-1 font-serif text-xl text-violet-100">Работа в защищённом владении</h3>
              <p class="mt-2 text-sm leading-6 text-stone-300">
                Здесь можно перейти к гримуару, мастерской и алхимическому столу. Их команды снова проверят
                ваше владение и материалы на стороне мира.
              </p>
              <div class="mt-4 flex flex-wrap gap-2">
                <.link
                  id="base-open-spellbook"
                  navigate={~p"/spellbook"}
                  class="rounded border border-violet-300/50 px-3 py-2 text-sm text-violet-100 transition hover:bg-violet-300/10"
                >
                  Гримуар
                </.link>
                <.link
                  id="base-open-craft"
                  navigate={~p"/craft"}
                  class="rounded border border-violet-300/50 px-3 py-2 text-sm text-violet-100 transition hover:bg-violet-300/10"
                >
                  Мастерская
                </.link>
                <.link
                  id="base-open-alchemy"
                  navigate={~p"/alchemy"}
                  class="rounded border border-violet-300/50 px-3 py-2 text-sm text-violet-100 transition hover:bg-violet-300/10"
                >
                  Алхимия
                </.link>
              </div>
            </section>

            <section
              :if={@ownership.via_organization?}
              id="base-shared-workbench-notice"
              class="mt-6 rounded-xl border border-violet-400/20 bg-violet-950/15 p-5"
            >
              <p class="text-xs uppercase tracking-[0.2em] text-violet-200/75">личные мастерские</p>
              <p class="mt-2 text-sm leading-6 text-stone-300">
                Общая доля открывает склад и отдых. Личные алхимические и ремесленные столы остаются
                привязанными к собственному владению персонажа.
              </p>
            </section>
          </section>

          <section
            :if={@building_base}
            id="base-building"
            class="rounded-xl border border-amber-500/25 bg-amber-950/15 p-6"
          >
            <h2 class="font-serif text-2xl text-amber-100">{@building_base.name}</h2>
            <p class="mt-2 text-sm text-stone-300">
              Строительство начато. Рабочие закончат его по игровому времени.
            </p>
            <p class="mt-2 text-sm text-amber-100/80">
              Готовность: {format_time(@building_base.ready_at)}
            </p>
          </section>

          <section
            :if={@can_establish?}
            id="base-establish"
            class="rounded-xl border border-amber-500/25 bg-stone-900/70 p-6"
          >
            <h2 class="font-serif text-2xl text-amber-100">
              {if @location.kind == :city,
                do: "Купить городское жильё",
                else: "Начать строительство базы"}
            </h2>
            <p class="mt-2 text-sm text-stone-400">
              {if @location.kind == :city,
                do: "Городское жильё сразу даёт защищённое хранилище.",
                else: "Полевое владение станет доступно после завершения строительства."}
            </p>
            <.form
              for={@establish_form}
              id="base-establish-form"
              phx-submit="establish"
              class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-end"
            >
              <.input
                field={@establish_form[:name]}
                type="text"
                label="Название"
                placeholder="Моё владение"
              />
              <button
                id="base-establish-submit"
                type="submit"
                class="mb-4 rounded-md bg-amber-300 px-4 py-3 font-semibold text-stone-950 transition hover:bg-amber-200"
              >
                {if @location.kind == :city, do: "Оформить", else: "Начать"}
              </button>
            </.form>
          </section>

          <section
            id="base-other-bases"
            class="rounded-xl border border-stone-700 bg-stone-900/60 p-5"
          >
            <h2 class="font-serif text-xl text-stone-100">Доступные владения</h2>
            <p :if={@bases == []} class="mt-2 text-sm text-stone-400">
              У вас пока нет других доступных владений.
            </p>
            <ul class="mt-3 space-y-2 text-sm text-stone-300">
              <li
                :for={base <- @bases}
                id={"base-known-#{base.id}"}
                class="flex justify-between rounded bg-stone-950/35 px-3 py-2"
              >
                <span>{base.name} · {base.location.name}</span><span>{base.status}</span>
              </li>
            </ul>
            <button
              id="base-refresh"
              type="button"
              phx-click="refresh"
              class="mt-4 text-sm text-amber-200 underline decoration-amber-500/40 underline-offset-4"
            >
              Обновить состояние
            </button>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp load_base(socket, character, selected_base_id) do
    case Play.base_state(character.id, selected_base_id) do
      {:ok, state} ->
        socket |> assign(:page_title, "База") |> assign(:error, nil) |> assign_base(state)

      {:error, :travelling} ->
        socket |> push_navigate(to: ~p"/travel")

      {:error, :base_not_accessible} ->
        socket |> push_navigate(to: ~p"/base")

      {:error, _reason} ->
        socket |> push_navigate(to: ~p"/map")
    end
  end

  defp refresh_base(socket) do
    case Play.base_state(socket.assigns.character.id, socket.assigns.selected_base_id) do
      {:ok, state} -> socket |> assign(:error, nil) |> assign_base(state)
      {:error, :travelling} -> push_navigate(socket, to: ~p"/travel")
      {:error, :base_not_accessible} -> push_navigate(socket, to: ~p"/base")
      {:error, _reason} -> assign(socket, :error, "Владение сейчас недоступно.")
    end
  end

  defp assign_base(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:location, state.location)
    |> assign(:bases, state.bases)
    |> assign(:active_base, state.active_base)
    |> assign(:active_base_choices, state.active_base_choices)
    |> assign(:requires_base_selection?, state.requires_base_selection?)
    |> assign(:building_base, state.building_base)
    |> assign(:storage_items, state.storage_items)
    |> assign(:carried_items, Enum.filter(state.carried_items, &(&1.quantity > 0)))
    |> assign(:storage_weight, state.storage_weight)
    |> assign(:storage_capacity, state.storage_capacity)
    |> assign(:can_establish?, state.can_establish?)
    |> assign(:ownership, state.ownership)
    |> assign(:selected_base_id, if(state.active_base, do: state.active_base.id, else: nil))
    |> assign(:can_rest?, state.can_rest?)
    |> assign(:survival, state.survival)
    |> assign(:carried_options, item_options(state.carried_items))
    |> assign(:storage_options, item_options(state.storage_items))
    |> assign(:establish_form, to_form(%{"name" => ""}, as: :base_establish))
    |> assign(
      :deposit_form,
      to_form(%{"inventory_item_id" => "", "quantity" => "1"}, as: :base_deposit)
    )
    |> assign(
      :withdraw_form,
      to_form(%{"storage_item_id" => "", "quantity" => "1"}, as: :base_withdraw)
    )
    |> assign(:ownership_options, ownership_options(state.ownership))
    |> assign(
      :ownership_form,
      to_form(%{"organization_id" => "", "share_bps" => "0"}, as: :base_ownership)
    )
  end

  defp item_options(items) do
    Enum.map(items, fn item -> {"#{item.item_template.name} ×#{item.quantity}", item.id} end)
  end

  defp parse_quantity(quantity) when is_binary(quantity) do
    case Integer.parse(quantity) do
      {number, ""} when number > 0 -> {:ok, number}
      _other -> {:error, :invalid_quantity}
    end
  end

  defp parse_quantity(_quantity), do: {:error, :invalid_quantity}

  defp parse_share_bps(share_bps) when is_binary(share_bps) do
    case Integer.parse(share_bps) do
      {number, ""} when number in 0..9_999 -> {:ok, number}
      _other -> {:error, :invalid_ownership_share}
    end
  end

  defp parse_share_bps(_share_bps), do: {:error, :invalid_ownership_share}

  defp ownership_options(nil), do: []

  defp ownership_options(ownership) do
    manageable = Map.new(ownership.manageable_organizations, &{&1.id, &1.name})

    share_holders =
      ownership.organization_shares
      |> Enum.map(fn share ->
        label =
          if Map.has_key?(manageable, share.organization_id) do
            share.organization_name
          else
            "#{share.organization_name} (доступно только снятие доли)"
          end

        {share.organization_id, label}
      end)
      |> Map.new()

    manageable
    |> Map.merge(share_holders)
    |> Enum.map(fn {organization_id, name} -> {name, organization_id} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp format_time(nil), do: "ожидает расчёта"
  defp format_time(time), do: Calendar.strftime(time, "%d.%m %H:%M UTC")

  defp error_message(:travelling), do: "Нельзя пользоваться базой во время пути."
  defp error_message(:active_base_not_found), do: "Здесь нет активной базы."
  defp error_message(:base_exists), do: "На этом месте уже есть ваше владение."
  defp error_message(:inventory_item_not_found), do: "Предмета нет в вашей котомке."
  defp error_message(:storage_item_not_found), do: "Предмета нет в этом хранилище."
  defp error_message(:invalid_quantity), do: "Укажите положительное количество."
  defp error_message(:invalid_ownership_share), do: "Укажите долю от 0 до 9999."
  defp error_message(:base_ownership_organization_not_found), do: "Организация больше недоступна."
  defp error_message(:base_ownership_unavailable), do: "Доля владения сейчас недоступна."

  defp error_message(_reason),
    do: "Команда не выполнена: проверьте место, вместимость и доступность предмета."
end
