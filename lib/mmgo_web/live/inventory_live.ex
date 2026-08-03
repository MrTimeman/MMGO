defmodule MMGOWeb.InventoryLive do
  @moduledoc """
  Server-authoritative carry inventory for the local play session.

  It presents the inventory and grimoire contexts through `MMGO.Play`; it does
  not invent equipment, selling, or disposal actions that the domain does not
  yet expose.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  alias MMGO.Play

  @categories ~w(все оружие зелья ингредиенты инструменты провизия гримуары)

  @impl true
  def mount(_params, _session, socket) do
    case Play.inventory_state(socket.assigns.current_scope.character) do
      {:ok, state} ->
        {:ok,
         socket
         |> assign(:page_title, "Котомка")
         |> assign(:categories, @categories)
         |> assign(:filter, "все")
         |> assign(:query, "")
         |> assign(:search_form, to_form(%{"q" => ""}, as: :inventory_search))
         |> assign(:selected, nil)
         |> assign_inventory_state(state)}

      {:error, _reason} ->
        {:ok, push_navigate(socket, to: ~p"/play")}
    end
  end

  @impl true
  def handle_event("filter", %{"cat" => cat}, socket) when cat in @categories do
    {:noreply, assign(socket, :filter, cat)}
  end

  def handle_event("filter", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", %{"inventory_search" => %{"q" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:search_form, to_form(%{"q" => query}, as: :inventory_search))}
  end

  @impl true
  def handle_event("open", %{"id" => id}, socket) do
    selected = if Enum.any?(socket.assigns.items, &(&1.id == id)), do: id, else: nil
    {:noreply, assign(socket, :selected, selected)}
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  @impl true
  def render(assigns) do
    visible = filter_items(assigns.items, assigns.filter, assigns.query)

    assigns =
      assigns
      |> assign(:visible, visible)
      |> assign(:selected_item, Enum.find(assigns.items, &(&1.id == assigns.selected)))
      |> assign(:pct, bar_pct(assigns.carry, assigns.carry_max))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="game-screen">
        <div id="inventory-screen" class="inv-root">
          <.link id="inventory-back-to-map" navigate={~p"/map"} class="inv-exit">
            &larr; на карту
          </.link>

          <header class="inv-head">
            <h1 class="inv-title">Котомка</h1>
            <p id="inventory-character-location" class="inv-sub">
              {@character.name} · {location_name(@current_location)}
            </p>

            <div class={["inv-carry", @pct >= 90 && "inv-carry--heavy"]}>
              <div class="inv-carry__top">
                <span class="inv-carry__label">Вес поклажи</span>
                <span id="inventory-carry" class="inv-carry__num">
                  {@carry} / {@carry_max} стоуна
                </span>
              </div>
              <div class="inv-carry__track">
                <div class="inv-carry__fill" style={"width:#{@pct}%"}></div>
              </div>
              <p class="inv-carry__hint">
                {if @pct >= 90,
                  do: "На пределе — из боя не сбежать",
                  else: "Есть ещё место под трофеи"}
              </p>
              <p id="inventory-overload-state" class="inv-carry__hint">
                {overload_status(@survival)}
              </p>
              <p id="inventory-survival-state" class="inv-carry__hint">
                {survival_status(@survival)}
              </p>
            </div>
          </header>

          <section class="inv-manifest" aria-label="Опись котомки">
            <div class="inv-manifest__clip" aria-hidden="true"></div>
            <p class="inv-manifest__folio">Дорожная опись · личная поклажа</p>

            <.form
              for={@search_form}
              id="inventory-search-form"
              phx-change="search"
              class="inv-search"
            >
              <.input
                field={@search_form[:q]}
                type="search"
                placeholder="Найти строку в описи…"
                autocomplete="off"
                class="inv-search__in"
              />
              <span class="inv-search__glass" aria-hidden="true">⌕</span>
            </.form>

            <nav
              id="inventory-categories"
              class="inv-chips"
              aria-label="Разделы описи"
            >
              <button
                :for={category <- @categories}
                id={"inventory-category-#{category}"}
                type="button"
                class={["inv-chip", @filter == category && "inv-chip--on"]}
                phx-click="filter"
                phx-value-cat={category}
              >
                {category}
              </button>
            </nav>

            <p :if={@visible == []} id="inventory-empty" class="inv-empty">
              В этом разделе описи строк нет.
            </p>

            <ul id="inventory-items" class="inv-list">
              <li
                :for={item <- @visible}
                id={"inventory-item-#{item.id}"}
              >
                <button
                  id={"inventory-open-#{item.id}"}
                  type="button"
                  class={["inv-item", item.equipped && "inv-item--equipped"]}
                  phx-click="open"
                  phx-value-id={item.id}
                  aria-label={"Подробнее: #{item.name}"}
                >
                  <.art_slot
                    kind="icon"
                    variant="parchment"
                    label={item.name}
                    class="inv-item__icon"
                  />
                  <span class="inv-item__body">
                    <span class="inv-item__name">
                      {item.name}<span :if={item.quantity > 1} class="inv-item__qty">×{item.quantity}</span>
                    </span>
                    <span class="inv-item__meta">
                      <span class="inv-chip inv-chip--tag">{item.category}</span>
                      <span :if={item.equipped} class="inv-item__eq">активен</span>
                      <span :if={item.reserved_quantity > 0} class="inv-item__eq">
                        занято: {item.reserved_quantity}
                      </span>
                    </span>
                  </span>
                  <span class="inv-item__right">
                    <span class="inv-item__weight">{item.weight * item.quantity} ст.</span>
                    <span class="inv-item__chevron" aria-hidden="true">смотреть</span>
                  </span>
                </button>
              </li>
            </ul>
          </section>

          <%= if @selected_item do %>
            <div id="inventory-detail-scrim" class="inv-sheet-scrim" phx-click="close">
              <div id="inventory-detail" class="inv-sheet" phx-click-away="close">
                <div class="inv-sheet__grab" aria-hidden="true">карточка предмета</div>
                <div class="inv-sheet__head">
                  <.art_slot
                    kind="scene"
                    variant="parchment"
                    label={@selected_item.name}
                    class="inv-sheet__art"
                  />
                  <div>
                    <h2 class="inv-sheet__name">{@selected_item.name}</h2>
                    <div class="inv-sheet__meta">
                      <span class="inv-chip inv-chip--tag">{@selected_item.category}</span>
                      <span class="inv-sheet__stat">{@selected_item.weight} стоуна / шт.</span>
                      <span class="inv-sheet__stat">
                        В наличии: {@selected_item.available_quantity}
                      </span>
                    </div>
                  </div>
                </div>

                <p class="inv-sheet__desc">{@selected_item.description}</p>

                <div class="inv-sheet__actions">
                  <button id="inventory-detail-close" type="button" class="inv-act" phx-click="close">
                    Убрать карточку
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp assign_inventory_state(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:current_location, state.current_location)
    |> assign(:items, item_rows(state.items, state.available_quantities, state.active_grimoire))
    |> assign(:food_units, state.food_units)
    |> assign(:carry, state.carried_weight)
    |> assign(:carry_max, state.carry_capacity)
    |> assign(:survival, state.survival)
  end

  defp item_rows(items, available_quantities, active_grimoire) do
    item_rows =
      items
      |> Enum.filter(&(&1.quantity > 0))
      |> Enum.map(&inventory_row(&1, available_quantities))

    case active_grimoire do
      nil -> item_rows
      grimoire -> [grimoire_row(grimoire) | item_rows]
    end
  end

  defp inventory_row(item, available_quantities) do
    template = item.item_template

    %{
      id: item.id,
      name: template.name,
      category: category_name(template.item_type),
      weight: template.weight,
      quantity: item.quantity,
      available_quantity: Map.fetch!(available_quantities, item.id),
      reserved_quantity: item.reserved_quantity,
      equipped: false,
      description:
        template.metadata["description"] || "Для этого предмета ещё не задано описание.",
      actions: Enum.map(template.actions || [], & &1.key)
    }
  end

  defp grimoire_row(grimoire) do
    %{
      id: "grimoire-#{grimoire.id}",
      name: grimoire.name,
      category: "гримуары",
      weight: grimoire.weight,
      quantity: 1,
      available_quantity: 1,
      reserved_quantity: 0,
      equipped: true,
      description: "Активный гримуар. Его вес уже учтён в вашей поклаже.",
      actions: []
    }
  end

  defp category_name(type) when type in [:weapon, :shield], do: "оружие"
  defp category_name(:potion), do: "зелья"
  defp category_name(:ingredient), do: "ингредиенты"
  defp category_name(:tool), do: "инструменты"
  defp category_name(:food), do: "провизия"

  defp filter_items(items, filter, query) do
    query = query |> String.trim() |> String.downcase()

    items
    |> Enum.filter(fn item -> filter == "все" or item.category == filter end)
    |> Enum.filter(fn item ->
      query == "" or String.contains?(String.downcase(item.name), query)
    end)
  end

  defp location_name(nil), do: "в пути"
  defp location_name(location), do: location.name

  defp overload_status(%{encumbered?: true, carried_weight: weight, carry_capacity: capacity}) do
    "Перегруз: #{weight} / #{capacity} стоунов. Отступление в бою недоступно."
  end

  defp overload_status(%{carried_weight: weight, carry_capacity: capacity}) do
    "Перегруза нет: #{weight} / #{capacity} стоунов."
  end

  defp survival_status(%{starving?: true, starvation_days: days, health_drain: health_drain}) do
    "Голод #{days} дн. · не-смертельный урон #{health_drain}. Еда снимет последствия."
  end

  defp survival_status(%{recovered?: true}), do: "Силы восстановлены после еды."
  defp survival_status(%{food_units: food_units}), do: "Провизия: #{food_units} ед. еды."

  defp bar_pct(_value, max) when max <= 0, do: 0

  defp bar_pct(value, max),
    do: value |> Kernel./(max) |> Kernel.*(100) |> min(100) |> max(0) |> round()
end
