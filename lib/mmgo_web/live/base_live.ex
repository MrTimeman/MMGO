defmodule MMGOWeb.BaseLive do
  @moduledoc """
  Scoped base, storage, and construction surface.

  Every transfer is reconstructed from `MMGO.Play` and the current location;
  this LiveView never receives a base owner or arbitrary storage authority from
  the browser.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play
  alias MMGO.Accounts.CharacterProfiles

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
      <main id="base-screen" class="game-root bse-root bse-root--live">
        <.link id="base-back-to-map" navigate={~p"/map"} class="bse-exit">
          ← выйти на карту
        </.link>

        <div class="bse-shell">
          <header class="bse-hero bse-hero--live">
            <div class="bse-hero__scene" aria-hidden="true">
              <span class="bse-hero__window"></span>
              <span class="bse-hero__desk"></span>
              <span class="bse-candle"></span>
            </div>
            <div class="bse-hero__veil"></div>
            <div class="bse-hero__caption">
              <span class="bse-hero__kind">защищённое владение · {@location.name}</span>
              <h1 class="bse-hero__name">
                {if @active_base, do: @active_base.name, else: "Комната ждёт хозяина"}
              </h1>
              <p id="base-carry-summary" class="bse-hero__where">
                {@character.name} · поклажа {Map.get(@survival, :carried_weight, 0)} / {Map.get(
                  @survival,
                  :carry_capacity,
                  0
                )}
              </p>
            </div>
          </header>

          <div
            :if={@error}
            id="base-error"
            class="bse-alert"
          >
            {@error}
          </div>

          <section
            :if={@requires_base_selection?}
            id="base-accessible-choices"
            class="bse-deed bse-deed--keys"
          >
            <p class="bse-deed__eyebrow">общие ключи</p>
            <h2 class="bse-deed__title">Выберите доступную базу</h2>
            <p class="bse-deed__copy">
              В этой точке доступно несколько общих владений. База выбирается явно, а право на
              каждую операцию будет заново проверено на стороне мира.
            </p>
            <div class="bse-keyring">
              <.link
                :for={base <- @active_base_choices}
                id={"base-select-#{base.id}"}
                navigate={~p"/base/#{base.id}"}
                class="bse-key"
              >
                <span class="bse-key__bow" aria-hidden="true">◉</span>
                <span class="bse-key__label">
                  <b>{base.name}</b>
                  {if base.direct_owner?, do: "личное владение", else: "общий доступ организации"} ·
                  вместимость {base.storage_capacity}
                </span>
              </.link>
            </div>
          </section>

          <section
            :if={@active_base}
            id="base-active"
            class="bse-room"
          >
            <div class="bse-status">
              <div class="bse-status__row">
                <span class="bse-status__key">Владение</span>
                <span class="bse-status__val">{@active_base.name}</span>
              </div>
              <p class="bse-status__note">
                Вещи внутри нельзя отнять; использовать их можно только вернувшись сюда.
              </p>
              <div
                :if={@fortress}
                id="base-fortress-status"
                class="bse-ward bse-ward--fortress"
              >
                <span class="bse-ward__sigil" aria-hidden="true">✦</span>
                <div>
                  <p class="bse-ward__title">
                    Личная крепость · ранг {@fortress.tier} из 5
                  </p>
                  <p class="bse-ward__body">
                    Пока владелец действительно находится здесь, стены дают ему начальный
                    боевой оберег силой {@fortress.ward_intensity}. За пределами Башни защита не
                    действует.
                  </p>
                </div>
              </div>
              <div class="bse-ward bse-ward--safe">
                <span class="bse-ward__sigil">❖</span>
                <div>
                  <p class="bse-ward__title">Порог под защитой</p>
                  <p class="bse-ward__body">
                    Ключи и права на каждое действие проверяются самим миром.
                  </p>
                </div>
                <span id="base-storage-capacity" class="bse-capacity">
                  {@storage_weight} / {@storage_capacity} веса
                </span>
              </div>
            </div>

            <section id="base-ownership" class="bse-deed bse-deed--ownership">
              <p class="bse-deed__eyebrow">титульная запись · доли и ключи</p>
              <h3 class="bse-deed__title">Совместное владение</h3>
              <p
                :if={@ownership.via_organization?}
                id="base-access-via-organization"
                class="bse-deed__seal-note"
              >
                Вы здесь как хранитель организации. Вклад и выдача предметов, а также отдых,
                происходят из общих запасов этой базы.
              </p>
              <p class="bse-deed__copy">
                Титульному владельцу принадлежит {@ownership.owner_share_bps} из 10 000 долей.
                Положительная доля организации открывает реальные ключи от склада только её
                действующим казначеям.
              </p>
              <ul id="base-organization-shares" class="bse-deed__entries">
                <li
                  :for={share <- @ownership.organization_shares}
                  id={"base-organization-share-#{share.organization_id}"}
                >
                  <span>{share.organization_name}</span>
                  <b>
                    {share.share_bps} / 10 000 {if share.active?, do: "долей", else: "долей · архив"}
                  </b>
                </li>
                <li
                  :if={@ownership.organization_shares == []}
                  id="base-organization-shares-empty"
                  class="bse-deed__empty"
                >
                  У этой базы пока нет организации-сособственника.
                </li>
              </ul>

              <.form
                :if={@ownership.is_owner? and @ownership_options != []}
                for={@ownership_form}
                id="base-organization-ownership-form"
                phx-submit="configure_organization_ownership"
                class="bse-form bse-form--deed"
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
                  class="bse-seal-button"
                >
                  Обновить долю
                </button>
              </.form>
              <p
                :if={@ownership.is_owner? and @ownership_options == []}
                id="base-organization-ownership-unavailable"
                class="bse-deed__margin-note"
              >
                Чтобы выдать долю, сначала станьте казначеем подходящей организации.
              </p>
            </section>

            <section class="bse-storage">
              <header class="bse-storage__head">
                <div>
                  <p class="bse-storage__eyebrow">сундуки и полки</p>
                  <h2>Хранилище</h2>
                </div>
                <span class="bse-storage__mark" aria-hidden="true">⌑</span>
              </header>

              <div class="bse-storage__transfers">
                <section class="bse-storage__tray">
                  <h3>Внести из котомки</h3>
                  <p :if={@carried_items == []} id="base-carried-empty" class="bse-empty">
                    В котомке нет предметов для хранения.
                  </p>
                  <.form
                    :if={@carried_items != []}
                    for={@deposit_form}
                    id="base-deposit-form"
                    phx-submit="deposit"
                    class="bse-form"
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
                    <button id="base-deposit" type="submit" class="bse-station__act">
                      В хранилище
                    </button>
                  </.form>
                </section>

                <section class="bse-storage__tray">
                  <h3>Взять с полки</h3>
                  <p :if={@storage_items == []} id="base-storage-empty" class="bse-empty">
                    Хранилище пока пусто.
                  </p>
                  <.form
                    :if={@storage_items != []}
                    for={@withdraw_form}
                    id="base-withdraw-form"
                    phx-submit="withdraw"
                    class="bse-form"
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
                      class="bse-station__act bse-station__act--rest"
                    >
                      В котомку
                    </button>
                  </.form>
                </section>
              </div>

              <div class="bse-storage__inventory">
                <section>
                  <h3>Котомка у двери</h3>
                  <ul id="base-carried-items" class="bse-crate-list">
                    <li
                      :for={item <- @carried_items}
                      id={"base-carried-#{item.id}"}
                    >
                      <span>{item.item_template.name}</span><b>×{item.quantity}</b>
                    </li>
                  </ul>
                </section>
                <section>
                  <h3>За запертой дверцей</h3>
                  <ul id="base-storage-items" class="bse-crate-list bse-crate-list--stored">
                    <li
                      :for={item <- @storage_items}
                      id={"base-storage-#{item.id}"}
                    >
                      <span>{item.item_template.name}</span><b>×{item.quantity}</b>
                    </li>
                  </ul>
                </section>
              </div>
            </section>

            <h2 class="bse-sec-title">Комната</h2>
            <section id="base-rest" class="bse-stations">
              <div class="bse-station bse-station--rest">
                <span class="bse-station__glyph">☾</span>
                <div class="bse-station__body">
                  <span class="bse-station__title">Отдых у своих запасов</span>
                  <p id="base-rest-state" class="bse-station__desc">
                    <%= cond do %>
                      <% @can_rest? -> %>
                        Голод и дорожный урон можно снять: отдых съест одну порцию провизии из
                        хранилища.
                      <% @survival.recovered? -> %>
                        Силы уже восстановлены; следующая дорога снова будет рассчитываться по
                        реальным запасам.
                      <% @survival.starving? or @survival.health_drain > 0 -> %>
                        Для восстановления положите в хранилище съедобную провизию.
                      <% true -> %>
                        Сейчас нет голодных последствий, которые нужно снимать отдыхом.
                    <% end %>
                  </p>
                </div>
                <button
                  :if={@can_rest?}
                  id="base-rest-submit"
                  type="button"
                  phx-click="rest"
                  class="bse-station__act bse-station__act--rest"
                >
                  Поесть и отдохнуть
                </button>
              </div>
            </section>

            <section :if={not @ownership.via_organization?} id="base-workbench" class="bse-workbench">
              <div class="bse-workbench__head">
                <div>
                  <p class="bse-workbench__eyebrow">рабочее место</p>
                  <h2>Столы и инструменты</h2>
                </div>
                <span class="bse-workbench__lamp" aria-hidden="true"></span>
              </div>
              <p class="bse-workbench__copy">
                Каждый стол открывает свою рабочую поверхность; право владения и материалы снова
                проверит мир.
              </p>
              <div class="bse-stations bse-stations--workbench">
                <.link id="base-open-spellbook" navigate={~p"/spellbook"} class="bse-station">
                  <span class="bse-station__glyph bse-station__glyph--book">▥</span>
                  <span class="bse-station__body">
                    <span class="bse-station__title">Гримуар на пюпитре</span>
                    <span class="bse-station__desc">Формулы, боевые раскладки и печати.</span>
                  </span>
                  <span class="bse-station__arrow">→</span>
                </.link>
                <.link id="base-open-craft" navigate={~p"/craft"} class="bse-station">
                  <span class="bse-station__glyph bse-station__glyph--anvil">⚒</span>
                  <span class="bse-station__body">
                    <span class="bse-station__title">Верстак и горн</span>
                    <span class="bse-station__desc">
                      Огонь, наковальня и инструменты ремесленника.
                    </span>
                  </span>
                  <span class="bse-station__arrow">→</span>
                </.link>
                <.link id="base-open-alchemy" navigate={~p"/alchemy"} class="bse-station">
                  <span class="bse-station__glyph bse-station__glyph--alchemy">⚗</span>
                  <span class="bse-station__body">
                    <span class="bse-station__title">Алхимический стол</span>
                    <span class="bse-station__desc">Ступка, реторта и полка с реагентами.</span>
                  </span>
                  <span class="bse-station__arrow">→</span>
                </.link>
              </div>
            </section>

            <section
              :if={@ownership.via_organization?}
              id="base-shared-workbench-notice"
              class="bse-deed bse-deed--muted"
            >
              <p class="bse-deed__eyebrow">личные мастерские</p>
              <p class="bse-deed__copy">
                Общая доля открывает склад и отдых. Личные алхимические и ремесленные столы остаются
                привязанными к собственному владению персонажа.
              </p>
            </section>
          </section>

          <section :if={@building_base} id="base-building" class="bse-building">
            <span class="bse-building__mark" aria-hidden="true">⌂</span>
            <div>
              <p class="bse-deed__eyebrow">стройка под надзором</p>
              <h2>{@building_base.name}</h2>
              <p>Рабочие закончат владение по игровому времени.</p>
              <b>Готовность: {format_time(@building_base.ready_at)}</b>
            </div>
          </section>

          <section :if={@can_establish?} id="base-establish" class="bse-deed bse-deed--acquisition">
            <p class="bse-deed__eyebrow">купчая и строительная запись</p>
            <h2 class="bse-deed__title">
              {if @location.kind == :city,
                do: "Купить городское жильё",
                else: "Начать строительство базы"}
            </h2>
            <p class="bse-deed__copy">
              {if @location.kind == :city,
                do: "Городское жильё сразу даёт защищённое хранилище после оплаты.",
                else:
                  "Полевое владение станет доступно после оплаты, материалов и завершения строительства."}
            </p>
            <div id="base-acquisition-quote" class="bse-quote">
              <p>
                Цена: <b>{@acquisition_quote.subtotal} ◈</b>
                + налог {@acquisition_quote.tax_amount} ◈ ({format_tax_rate(
                  @acquisition_quote.tax_rate_bps
                )}) = <strong>{@acquisition_quote.total_coin_cost} ◈</strong>
              </p>
              <p>Ваш кошель: {@balance} ◈</p>
              <p :if={@acquisition_quote.build_days > 0}>
                Срок: {@acquisition_quote.build_days} игровых дней
              </p>
              <ul :if={@acquisition_quote.materials != []} id="base-build-materials">
                <li :for={material <- @acquisition_quote.materials}>
                  {material_label(material.code)}: {material.available}/{material.quantity}
                </li>
              </ul>
            </div>
            <.form
              for={@establish_form}
              id="base-establish-form"
              phx-submit="establish"
              class="bse-form bse-form--establish"
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
                disabled={not @can_afford_acquisition?}
                class="bse-seal-button"
              >
                {if @location.kind == :city, do: "Оформить купчую", else: "Начать стройку"}
              </button>
            </.form>
          </section>

          <section id="base-other-bases" class="bse-keyboard">
            <div class="bse-keyboard__rail" aria-hidden="true"></div>
            <div class="bse-keyboard__head">
              <div>
                <p class="bse-deed__eyebrow">связка ключей</p>
                <h2>Доступные владения</h2>
              </div>
              <button
                id="base-refresh"
                type="button"
                phx-click="refresh"
                class="bse-keyboard__refresh"
              >
                обновить
              </button>
            </div>
            <p :if={@bases == []} class="bse-empty">
              У вас пока нет других доступных владений.
            </p>
            <ul class="bse-known-bases">
              <li :for={base <- @bases} id={"base-known-#{base.id}"}>
                <span class="bse-key__bow" aria-hidden="true">◉</span>
                <span>{base.name}<small>{base.location.name}</small></span>
                <b>{base_status_label(base.status)}</b>
              </li>
            </ul>
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
    |> assign(:acquisition_quote, state.acquisition_quote)
    |> assign(:balance, state.balance)
    |> assign(:can_afford_acquisition?, state.can_afford_acquisition?)
    |> assign(:ownership, state.ownership)
    |> assign(:fortress, fortress_config(state.active_base, state.character))
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

  defp format_tax_rate(tax_rate_bps) do
    :erlang.float_to_binary(tax_rate_bps / 100, decimals: 2) <> "%"
  end

  defp base_status_label(:building), do: "строится"
  defp base_status_label(:active), do: "действует"
  defp base_status_label(:abandoned), do: "покинута"
  defp base_status_label(_status), do: "состояние уточняется"

  defp material_label("construction_material"), do: "строительные материалы"
  defp material_label(_code), do: "строительные припасы"

  defp fortress_config(
         %{location_id: location_id, metadata: %{"fortress" => fortress}},
         character
       )
       when is_map(fortress) do
    case fortress do
      %{"tier" => tier, "ward_intensity" => intensity}
      when tier in 1..5 and intensity in 1..100 ->
        if CharacterProfiles.sealed_spirit?(character) and
             CharacterProfiles.sealed_anchor_location_id(character) == location_id do
          %{tier: tier, ward_intensity: intensity}
        end

      _malformed ->
        nil
    end
  end

  defp fortress_config(_base, _character), do: nil

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
