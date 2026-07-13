defmodule MMGOWeb.TradeLive do
  @moduledoc """
  Scoped NPC, legal-market, and black-market transactions.

  Prices, item ownership, tax, escrow, and delivery are all validated by the
  owning domain contexts. This screen only presents real selections from the
  current player's server-built trade read model.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket) do
    load_trade(socket, socket.assigns.current_scope.character)
  end

  @impl true
  def handle_event("buy_shop", %{"offer-id" => offer_id}, socket) do
    transact(
      socket,
      fn -> Play.buy_shop_item(socket.assigns.character, offer_id, 1) end,
      "Покупка совершена."
    )
  end

  @impl true
  def handle_event("buy_grimoire", %{"tier" => tier}, socket) do
    transact(
      socket,
      fn -> Play.purchase_trade_grimoire(socket.assigns.character, tier) end,
      "Новый гримуар выкуплен и ждёт записи формул."
    )
  end

  @impl true
  def handle_event("sell_shop", %{"shop_sell" => params}, socket) do
    with {:ok, quantity} <- parse_positive(params["quantity"]),
         {:ok, _state} <-
           Play.sell_shop_item(
             socket.assigns.character,
             params["offer_id"],
             params["inventory_item_id"],
             quantity
           ) do
      {:noreply, socket |> put_flash(:info, "Лавочник принял товар.") |> refresh_trade()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("create_listing", %{"market_listing" => params}, socket) do
    with {:ok, quantity} <- parse_positive(params["quantity"]),
         {:ok, unit_price} <- parse_positive(params["unit_price"]),
         {:ok, _state} <-
           Play.create_market_listing(
             socket.assigns.character,
             params["inventory_item_id"],
             quantity,
             unit_price
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Объявление опубликовано с казённым налогом.")
       |> refresh_trade()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("buy_listing", %{"listing-id" => listing_id}, socket) do
    transact(
      socket,
      fn -> Play.purchase_market_listing(socket.assigns.character, listing_id) end,
      "Сделка записана в книгу рынка."
    )
  end

  @impl true
  def handle_event("cancel_listing", %{"listing-id" => listing_id}, socket) do
    transact(
      socket,
      fn -> Play.cancel_market_listing(socket.assigns.character, listing_id) end,
      "Объявление снято; резерв предмета освобождён."
    )
  end

  @impl true
  def handle_event("create_black_offer", %{"black_offer" => params}, socket) do
    with {:ok, quantity} <- parse_positive(params["quantity"]),
         {:ok, unit_price} <- parse_positive(params["unit_price"]),
         {:ok, _state} <-
           Play.create_black_market_offer(
             socket.assigns.character,
             params["inventory_item_id"],
             quantity,
             unit_price
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Тайное предложение оставлено без налоговой защиты.")
       |> refresh_trade()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def handle_event("accept_black_offer", %{"offer-id" => offer_id}, socket) do
    transact(
      socket,
      fn -> Play.accept_black_market_offer(socket.assigns.character, offer_id) end,
      "Оплата прошла. Теперь продавец обязан доставить товар."
    )
  end

  @impl true
  def handle_event("fulfill_black_deal", %{"deal-id" => deal_id}, socket) do
    transact(
      socket,
      fn -> Play.fulfill_black_market_deal(socket.assigns.character, deal_id) end,
      "Тайная сделка исполнена."
    )
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_trade(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="trade-screen" class="game-root min-h-full px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-4xl space-y-5">
          <.link id="trade-back-to-map" navigate={~p"/map"} class="map-back-link">← Карта мира</.link>

          <header class="rounded-xl border border-amber-500/25 bg-stone-900/80 p-6 shadow-xl">
            <p class="text-xs uppercase tracking-[0.22em] text-amber-300/70">
              торговая книга · {@location.name}
            </p>
            <div class="mt-2 flex flex-wrap items-end justify-between gap-3">
              <h1 class="font-serif text-3xl text-amber-100">Торговля</h1>
              <p
                id="trade-balance"
                class="rounded-full border border-amber-300/35 px-3 py-1 text-amber-100"
              >
                {@balance} ◈
              </p>
            </div>
          </header>

          <div
            :if={@error}
            id="trade-error"
            class="rounded-md border border-red-500/50 bg-red-950/30 px-4 py-3 text-sm text-red-200"
          >
            {@error}
          </div>

          <section id="trade-npc-shops" class="rounded-xl border border-stone-700 bg-stone-900/70 p-6">
            <h2 class="font-serif text-2xl text-stone-100">Лавки рядом</h2>
            <p :if={@shops == []} id="trade-shops-empty" class="mt-3 text-sm text-stone-400">
              В этом месте нет открытых лавок.
            </p>
            <div
              :for={shop <- @shops}
              id={"trade-shop-#{shop.id}"}
              class="mt-5 rounded-lg border border-stone-700 bg-stone-950/45 p-4"
            >
              <h3 class="font-serif text-lg text-amber-100">{shop.name}</h3>
              <p :if={shop.description} class="mt-1 text-sm text-stone-400">{shop.description}</p>
              <ul class="mt-3 divide-y divide-stone-800">
                <li
                  :for={offer <- shop.offers}
                  id={"trade-shop-offer-#{offer.id}"}
                  class="flex flex-wrap items-center justify-between gap-3 py-3 text-sm"
                >
                  <span>{offer.item_template.name}</span>
                  <span class="text-stone-400">
                    купить {offer.buy_price} ◈ · продать {offer.sell_price} ◈
                  </span>
                  <button
                    :if={offer.buy_price > 0}
                    id={"trade-buy-#{offer.id}"}
                    type="button"
                    phx-click="buy_shop"
                    phx-value-offer-id={offer.id}
                    class="rounded border border-amber-300/50 px-3 py-1.5 text-amber-100 hover:bg-amber-300/10"
                  >
                    Купить 1
                  </button>
                </li>
              </ul>
            </div>

            <.form
              :if={@sell_offer_options != [] and @inventory_options != []}
              for={@sell_form}
              id="trade-sell-form"
              phx-submit="sell_shop"
              class="mt-5 grid gap-3 md:grid-cols-4 md:items-end"
            >
              <.input
                field={@sell_form[:offer_id]}
                type="select"
                label="Лавка покупает"
                prompt="Выберите расценку"
                options={@sell_offer_options}
              />
              <.input
                field={@sell_form[:inventory_item_id]}
                type="select"
                label="Ваша вещь"
                prompt="Выберите предмет"
                options={@inventory_options}
              />
              <.input
                field={@sell_form[:quantity]}
                type="number"
                label="Количество"
                min="1"
                inputmode="numeric"
              />
              <button
                id="trade-sell"
                type="submit"
                class="mb-4 rounded-md border border-amber-300/50 px-4 py-3 font-semibold text-amber-100 hover:bg-amber-300/10"
              >
                Продать
              </button>
            </.form>
          </section>

          <section
            id="trade-grimoire-catalog"
            class="rounded-xl border border-amber-400/25 bg-amber-950/15 p-6"
          >
            <h2 class="font-serif text-2xl text-amber-100">Переплётная лавка</h2>
            <p class="mt-2 text-sm leading-6 text-stone-400">
              Гримуар покупается один раз: вместимость и вес переплёта не меняются. Новый том можно заполнить в кабинете формул, а запечатанный заменить только другой книгой.
            </p>
            <div class="mt-5 grid gap-3 md:grid-cols-2">
              <article
                :for={tier <- @grimoire_tiers}
                id={"trade-grimoire-tier-#{tier.key}"}
                class="rounded-lg border border-amber-200/15 bg-stone-950/45 p-4"
              >
                <div class="flex items-start justify-between gap-3">
                  <div>
                    <h3 class="font-serif text-lg text-amber-100">{tier.name}</h3>
                    <p class="mt-1 text-sm text-stone-400">
                      {tier.capacity} формул · вес {tier.weight}
                    </p>
                  </div>
                  <span class="shrink-0 rounded-full border border-amber-300/25 px-2.5 py-1 text-sm text-amber-100">
                    {tier.price} ◈
                  </span>
                </div>
                <button
                  id={"trade-buy-grimoire-#{tier.key}"}
                  type="button"
                  phx-click="buy_grimoire"
                  phx-value-tier={tier.key}
                  class="mt-4 rounded border border-amber-300/50 px-3 py-1.5 text-sm font-semibold text-amber-100 transition hover:bg-amber-300/10"
                >
                  Купить переплёт
                </button>
              </article>
            </div>
          </section>

          <section
            :if={@legal_market_enabled?}
            id="trade-legal-market"
            class="rounded-xl border border-emerald-500/25 bg-emerald-950/15 p-6"
          >
            <h2 class="font-serif text-2xl text-emerald-100">Официальный рынок</h2>
            <p class="mt-2 text-sm text-stone-400">
              Налог при продаже: {@legal_market_tax_rate_bps / 100}% — он идёт в казну автоматически.
            </p>

            <.form
              :if={@inventory_options != []}
              for={@listing_form}
              id="trade-listing-form"
              phx-submit="create_listing"
              class="mt-5 grid gap-3 md:grid-cols-4 md:items-end"
            >
              <.input
                field={@listing_form[:inventory_item_id]}
                type="select"
                label="Ваш предмет"
                prompt="Выберите предмет"
                options={@inventory_options}
              />
              <.input
                field={@listing_form[:quantity]}
                type="number"
                label="Количество"
                min="1"
                inputmode="numeric"
              />
              <.input
                field={@listing_form[:unit_price]}
                type="number"
                label="Цена за единицу"
                min="1"
                inputmode="numeric"
              />
              <button
                id="trade-create-listing"
                type="submit"
                class="mb-4 rounded-md bg-emerald-300 px-4 py-3 font-semibold text-stone-950 hover:bg-emerald-200"
              >
                Выставить
              </button>
            </.form>

            <p
              :if={@market_listings == []}
              id="trade-listings-empty"
              class="mt-5 text-sm text-stone-400"
            >
              На рынке пока нет объявлений.
            </p>
            <ul id="trade-market-listings" class="mt-4 space-y-2">
              <li
                :for={listing <- @market_listings}
                id={"trade-listing-#{listing.id}"}
                class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-stone-700 bg-stone-950/45 p-3 text-sm"
              >
                <span>
                  {listing.item_template.name} ×{listing.quantity} · {listing.total_price} ◈
                </span>
                <div class="flex gap-2">
                  <button
                    :if={listing.seller_character_id != @character.id}
                    id={"trade-buy-listing-#{listing.id}"}
                    type="button"
                    phx-click="buy_listing"
                    phx-value-listing-id={listing.id}
                    class="rounded border border-emerald-300/50 px-3 py-1.5 text-emerald-100"
                  >
                    Купить
                  </button>
                  <button
                    :if={listing.seller_character_id == @character.id}
                    id={"trade-cancel-listing-#{listing.id}"}
                    type="button"
                    phx-click="cancel_listing"
                    phx-value-listing-id={listing.id}
                    class="rounded border border-stone-500 px-3 py-1.5 text-stone-200"
                  >
                    Снять
                  </button>
                </div>
              </li>
            </ul>
          </section>

          <section
            :if={@black_market_enabled?}
            id="trade-black-market"
            class="rounded-xl border border-violet-500/25 bg-violet-950/15 p-6"
          >
            <h2 class="font-serif text-2xl text-violet-100">Чёрный рынок</h2>
            <p class="mt-2 text-sm text-stone-400">
              Здесь нет налога и нет гарантии доставки: после оплаты товар остаётся обещанием продавца.
            </p>

            <.form
              :if={@inventory_options != []}
              for={@black_offer_form}
              id="trade-black-offer-form"
              phx-submit="create_black_offer"
              class="mt-5 grid gap-3 md:grid-cols-4 md:items-end"
            >
              <.input
                field={@black_offer_form[:inventory_item_id]}
                type="select"
                label="Ваш предмет"
                prompt="Выберите предмет"
                options={@inventory_options}
              />
              <.input
                field={@black_offer_form[:quantity]}
                type="number"
                label="Количество"
                min="1"
                inputmode="numeric"
              />
              <.input
                field={@black_offer_form[:unit_price]}
                type="number"
                label="Цена за единицу"
                min="1"
                inputmode="numeric"
              />
              <button
                id="trade-create-black-offer"
                type="submit"
                class="mb-4 rounded-md bg-violet-300 px-4 py-3 font-semibold text-stone-950 hover:bg-violet-200"
              >
                Предложить
              </button>
            </.form>

            <p
              :if={@black_market_offers == []}
              id="trade-black-offers-empty"
              class="mt-5 text-sm text-stone-400"
            >
              Тайных предложений пока нет.
            </p>
            <ul id="trade-black-offers" class="mt-4 space-y-2">
              <li
                :for={offer <- @black_market_offers}
                id={"trade-black-offer-#{offer.id}"}
                class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-stone-700 bg-stone-950/45 p-3 text-sm"
              >
                <span>{offer.item_template.name} ×{offer.quantity} · {offer.total_price} ◈</span>
                <button
                  :if={offer.seller_character_id != @character.id}
                  id={"trade-accept-black-offer-#{offer.id}"}
                  type="button"
                  phx-click="accept_black_offer"
                  phx-value-offer-id={offer.id}
                  class="rounded border border-violet-300/50 px-3 py-1.5 text-violet-100"
                >
                  Оплатить
                </button>
              </li>
            </ul>

            <div :if={@black_market_deals != []} id="trade-black-deals" class="mt-5 space-y-2">
              <h3 class="font-serif text-lg text-violet-100">Ваши обязательства</h3>
              <article
                :for={deal <- @black_market_deals}
                id={"trade-black-deal-#{deal.id}"}
                class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-stone-700 bg-stone-950/45 p-3 text-sm"
              >
                <span>{deal.item_template.name} ×{deal.quantity} · {deal.status}</span>
                <button
                  :if={
                    deal.seller_character_id == @character.id and deal.status == :awaiting_delivery
                  }
                  id={"trade-fulfill-black-deal-#{deal.id}"}
                  type="button"
                  phx-click="fulfill_black_deal"
                  phx-value-deal-id={deal.id}
                  class="rounded border border-violet-300/50 px-3 py-1.5 text-violet-100"
                >
                  Доставить
                </button>
              </article>
            </div>
          </section>

          <button
            id="trade-refresh"
            type="button"
            phx-click="refresh"
            class="text-sm text-amber-200 underline decoration-amber-500/40 underline-offset-4"
          >
            Обновить торговую книгу
          </button>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp transact(socket, command, message) do
    case command.() do
      {:ok, _state} -> {:noreply, socket |> put_flash(:info, message) |> refresh_trade()}
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  defp load_trade(socket, character) do
    case Play.trade_state(character) do
      {:ok, state} ->
        {:ok,
         socket |> assign(:page_title, "Торговля") |> assign(:error, nil) |> assign_trade(state)}

      {:error, :travelling} ->
        {:ok, push_navigate(socket, to: ~p"/travel")}

      {:error, _reason} ->
        {:ok, push_navigate(socket, to: ~p"/map")}
    end
  end

  defp refresh_trade(socket) do
    case Play.trade_state(socket.assigns.character) do
      {:ok, state} -> socket |> assign(:error, nil) |> assign_trade(state)
      {:error, :travelling} -> push_navigate(socket, to: ~p"/travel")
      {:error, _reason} -> assign(socket, :error, "Торговая книга сейчас недоступна.")
    end
  end

  defp assign_trade(socket, state) do
    shop_offers = Enum.flat_map(state.shops, &(&1.offers || []))
    inventory_options = item_options(state.inventory)

    socket
    |> assign(:character, state.character)
    |> assign(:location, state.location)
    |> assign(:balance, state.balance)
    |> assign(:shops, state.shops)
    |> assign(:inventory_options, inventory_options)
    |> assign(:sell_offer_options, offer_options(shop_offers, :sell_price))
    |> assign(:legal_market_enabled?, state.legal_market_enabled?)
    |> assign(:black_market_enabled?, state.black_market_enabled?)
    |> assign(:market_listings, state.market_listings)
    |> assign(:black_market_offers, state.black_market_offers)
    |> assign(:black_market_deals, state.black_market_deals)
    |> assign(:grimoire_tiers, state.grimoire_tiers)
    |> assign(:legal_market_tax_rate_bps, state.legal_market_tax_rate_bps)
    |> assign(
      :sell_form,
      to_form(%{"offer_id" => "", "inventory_item_id" => "", "quantity" => "1"}, as: :shop_sell)
    )
    |> assign(
      :listing_form,
      to_form(%{"inventory_item_id" => "", "quantity" => "1", "unit_price" => "1"},
        as: :market_listing
      )
    )
    |> assign(
      :black_offer_form,
      to_form(%{"inventory_item_id" => "", "quantity" => "1", "unit_price" => "1"},
        as: :black_offer
      )
    )
  end

  defp item_options(items) do
    items
    |> Enum.filter(&(&1.quantity > &1.reserved_quantity))
    |> Enum.map(fn item ->
      {"#{item.item_template.name} ×#{item.quantity - item.reserved_quantity}", item.id}
    end)
  end

  defp offer_options(offers, field) do
    offers
    |> Enum.filter(&(Map.fetch!(&1, field) > 0))
    |> Enum.map(fn offer ->
      {"#{offer.item_template.name} · #{Map.fetch!(offer, field)} ◈", offer.id}
    end)
  end

  defp parse_positive(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _other -> {:error, :invalid_quantity}
    end
  end

  defp parse_positive(_value), do: {:error, :invalid_quantity}

  defp error_message(:invalid_quantity), do: "Укажите положительное количество и цену."
  defp error_message(:inventory_item_not_found), do: "Выбранного предмета нет в вашей котомке."
  defp error_message(:shop_offer_not_found), do: "Эта расценка больше не действует здесь."

  defp error_message(:shop_inventory_not_found),
    do: "Лавочник не может принять этот набор предметов."

  defp error_message(:market_listing_not_found), do: "Это объявление больше не доступно."
  defp error_message(:black_market_offer_not_found), do: "Тайное предложение больше не доступно."
  defp error_message(:black_market_deal_not_found), do: "Эта тайная сделка больше не доступна."

  defp error_message(:legal_market_disabled),
    do: "В этом королевстве официальный рынок закрыт правилами мира."

  defp error_message(:black_market_disabled),
    do: "В этом королевстве чёрный рынок запрещён правилами мира."

  defp error_message(:travelling), do: "Нельзя торговать во время пути."
  defp error_message(:invalid_grimoire_tier), do: "Такого переплёта нет в каталоге лавки."

  defp error_message(_reason),
    do: "Сделка не выполнена: проверьте баланс, предмет и условия рынка."
end
