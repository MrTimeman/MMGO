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
  def handle_event("default_black_deal", %{"deal-id" => deal_id}, socket) do
    transact(
      socket,
      fn -> Play.default_black_market_deal(socket.assigns.character, deal_id) end,
      "Срок доставки истёк. Нарушение записано, продавцу назначены санкции."
    )
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_trade(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="trade-screen" class="game-root trd-root trd-root--live">
        <.link id="trade-back-to-map" navigate={~p"/map"} class="trd-exit">
          ← на площадь
        </.link>

        <div class="trd-shell trd-shell--live">
          <header class="trd-head trd-stall">
            <div class="trd-stall__awning" aria-hidden="true"></div>
            <div class="trd-stall__scene" aria-hidden="true">
              <span class="trd-stall__lantern"></span>
              <span class="trd-stall__shelves"></span>
              <span class="trd-stall__keeper"></span>
              <span class="trd-stall__counter"></span>
            </div>
            <div class="trd-head__bar">
              <div class="trd-head__who">
                <span class="trd-head__keeper">торговый ряд · {@location.name}</span>
                <h1 class="trd-head__shop">Лавки и рынок</h1>
              </div>
              <p id="trade-balance" class="trd-purse" title="ваш кошель">
                <span class="trd-coin">◈</span>
                <span class="trd-purse__n">{@balance}</span>
              </p>
            </div>
          </header>

          <div :if={@error} id="trade-error" class="trd-warn">
            {@error}
          </div>

          <section id="trade-npc-shops" class="trd-counter-section">
            <div class="trd-section-head">
              <div>
                <span class="trd-section-head__eyebrow">товар на прилавке</span>
                <h2>Лавки рядом</h2>
              </div>
              <span class="trd-section-head__chalk" aria-hidden="true">цена мелом</span>
            </div>
            <p :if={@shops == []} id="trade-shops-empty" class="trd-empty">
              В этом месте нет открытых лавок.
            </p>
            <article :for={shop <- @shops} id={"trade-shop-#{shop.id}"} class="trd-shop">
              <header class="trd-shop__sign">
                <span aria-hidden="true">✦</span>
                <div>
                  <h3>{shop.name}</h3>
                  <p :if={shop.description}>{shop.description}</p>
                </div>
              </header>
              <ul class="trd-goods">
                <li
                  :for={offer <- shop.offers}
                  id={"trade-shop-offer-#{offer.id}"}
                  class="trd-good"
                >
                  <span class="trd-good__icon" aria-hidden="true">◇</span>
                  <span class="trd-good__body">
                    <b class="trd-good__name">{offer.item_template.name}</b>
                    <span class="trd-good__note">
                      лавка берёт за <span class="trd-coin">◈</span>{offer.sell_price}
                    </span>
                  </span>
                  <span class="trd-good__deal">
                    <span class="trd-good__price">
                      <span class="trd-coin">◈</span>{offer.buy_price}
                    </span>
                    <button
                      :if={offer.buy_price > 0}
                      id={"trade-buy-#{offer.id}"}
                      type="button"
                      phx-click="buy_shop"
                      phx-value-offer-id={offer.id}
                      class="trd-add"
                    >
                      Купить 1
                    </button>
                  </span>
                </li>
              </ul>
            </article>

            <div
              :if={@sell_offer_options != [] and @inventory_options != []}
              class="trd-receipt trd-receipt--inline"
            >
              <div class="trd-receipt__deckle"></div>
              <h3 class="trd-receipt__title">Расписка на продажу</h3>
              <p class="trd-receipt__place">Лавочник заполнит сумму после передачи товара</p>
              <.form for={@sell_form} id="trade-sell-form" phx-submit="sell_shop" class="trd-form">
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
                <button id="trade-sell" type="submit" class="trd-receipt__seal">
                  Ударить по рукам
                </button>
              </.form>
              <div class="trd-receipt__stamp">торговый ряд</div>
            </div>
          </section>

          <section id="trade-grimoire-catalog" class="trd-bindery">
            <div class="trd-section-head">
              <div>
                <span class="trd-section-head__eyebrow">переплётная мастерская</span>
                <h2>Полка чистых гримуаров</h2>
              </div>
            </div>
            <p class="trd-bindery__copy">
              Гримуар покупается один раз: вместимость и вес переплёта не меняются. Новый том можно
              заполнить в кабинете формул, а запечатанный заменить только другой книгой.
            </p>
            <div class="trd-grimoire-shelf">
              <article
                :for={tier <- @grimoire_tiers}
                id={"trade-grimoire-tier-#{tier.key}"}
                class="trd-volume"
              >
                <span class="trd-volume__bands" aria-hidden="true"></span>
                <h3>{tier.name}</h3>
                <p>{tier.capacity} формул · вес {tier.weight}</p>
                <span class="trd-volume__price"><span class="trd-coin">◈</span>{tier.price}</span>
                <button
                  id={"trade-buy-grimoire-#{tier.key}"}
                  type="button"
                  phx-click="buy_grimoire"
                  phx-value-tier={tier.key}
                  class="trd-volume__buy"
                >
                  снять с полки
                </button>
              </article>
            </div>
            <div class="trd-grimoire-shelf__plank" aria-hidden="true"></div>
          </section>

          <section
            :if={@legal_market_enabled?}
            id="trade-legal-market"
            class="trd-market-board trd-market-board--legal"
          >
            <span class="trd-market-board__nail trd-market-board__nail--left" aria-hidden="true">
            </span>
            <span class="trd-market-board__nail trd-market-board__nail--right" aria-hidden="true">
            </span>
            <p class="trd-market-board__eyebrow">доска с княжеской печатью</p>
            <h2>Официальный рынок</h2>
            <p class="trd-market-board__copy">
              Налог при продаже: {@legal_market_tax_rate_bps / 100}% — он идёт в казну автоматически.
            </p>

            <.form
              :if={@inventory_options != []}
              for={@listing_form}
              id="trade-listing-form"
              phx-submit="create_listing"
              class="trd-form trd-posting-form"
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
                class="trd-posting-form__pin"
              >
                Приколоть объявление
              </button>
            </.form>

            <p :if={@market_listings == []} id="trade-listings-empty" class="trd-board-empty">
              На рынке пока нет объявлений.
            </p>
            <ul id="trade-market-listings" class="trd-notices">
              <li
                :for={listing <- @market_listings}
                id={"trade-listing-#{listing.id}"}
                class="trd-notice"
              >
                <span class="trd-notice__pin" aria-hidden="true"></span>
                <span class="trd-notice__copy">
                  {listing.item_template.name} ×{listing.quantity} · {listing.total_price} ◈
                </span>
                <span class="trd-notice__actions">
                  <button
                    :if={listing.seller_character_id != @character.id}
                    id={"trade-buy-listing-#{listing.id}"}
                    type="button"
                    phx-click="buy_listing"
                    phx-value-listing-id={listing.id}
                    class="trd-notice__act"
                  >
                    Купить
                  </button>
                  <button
                    :if={listing.seller_character_id == @character.id}
                    id={"trade-cancel-listing-#{listing.id}"}
                    type="button"
                    phx-click="cancel_listing"
                    phx-value-listing-id={listing.id}
                    class="trd-notice__act trd-notice__act--muted"
                  >
                    Снять
                  </button>
                </span>
              </li>
            </ul>
          </section>

          <section
            :if={@black_market_enabled?}
            id="trade-black-market"
            class="trd-market-board trd-market-board--black"
          >
            <span class="trd-market-board__nail trd-market-board__nail--left" aria-hidden="true">
            </span>
            <span class="trd-market-board__nail trd-market-board__nail--right" aria-hidden="true">
            </span>
            <p class="trd-market-board__eyebrow">записки за задней стеной</p>
            <h2>Чёрный рынок</h2>
            <p class="trd-market-board__copy">
              Здесь нет налога и нет гарантии доставки: после оплаты товар остаётся обещанием продавца.
            </p>

            <div
              :if={@inventory_options != []}
              class="trd-receipt trd-receipt--inline trd-receipt--black"
            >
              <div class="trd-receipt__deckle"></div>
              <h3 class="trd-receipt__title">Записка без подписи</h3>
              <p class="trd-receipt__place">Ни печати, ни защиты закона</p>
              <.form
                for={@black_offer_form}
                id="trade-black-offer-form"
                phx-submit="create_black_offer"
                class="trd-form"
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
                <button id="trade-create-black-offer" type="submit" class="trd-receipt__seal">
                  Оставить в тени
                </button>
              </.form>
            </div>

            <p :if={@black_market_offers == []} id="trade-black-offers-empty" class="trd-board-empty">
              Тайных предложений пока нет.
            </p>
            <ul id="trade-black-offers" class="trd-notices trd-notices--black">
              <li
                :for={offer <- @black_market_offers}
                id={"trade-black-offer-#{offer.id}"}
                class="trd-notice trd-notice--black"
              >
                <span class="trd-notice__pin" aria-hidden="true"></span>
                <span class="trd-notice__copy">
                  {offer.item_template.name} ×{offer.quantity} · {offer.total_price} ◈
                  <small>
                    риск дозора {format_bps(Map.fetch!(@black_market_risks, offer.id).chance_bps)} ·
                    штраф при поимке {Map.fetch!(@black_market_risks, offer.id).fine_amount} ◈
                  </small>
                </span>
                <button
                  :if={offer.seller_character_id != @character.id}
                  id={"trade-accept-black-offer-#{offer.id}"}
                  type="button"
                  phx-click="accept_black_offer"
                  phx-value-offer-id={offer.id}
                  class="trd-notice__act trd-notice__act--black"
                >
                  Оплатить
                </button>
              </li>
            </ul>

            <div :if={@black_market_deals != []} id="trade-black-deals" class="trd-obligations">
              <h3>Ваши обязательства</h3>
              <article
                :for={deal <- @black_market_deals}
                id={"trade-black-deal-#{deal.id}"}
                class="trd-obligation"
              >
                <span>
                  {deal.item_template.name} ×{deal.quantity} · {deal_status_label(deal.status)}
                  <small>срок доставки {delivery_due_label(deal)}</small>
                  <small
                    :if={get_in(deal.metadata || %{}, ["npc_detection", "caught"]) == true}
                    class="trd-obligation__caught"
                  >
                    Сделку заметил дозор; штраф списан, репутация снижена.
                  </small>
                </span>
                <button
                  :if={
                    deal.seller_character_id == @character.id and deal.status == :awaiting_delivery
                  }
                  id={"trade-fulfill-black-deal-#{deal.id}"}
                  type="button"
                  phx-click="fulfill_black_deal"
                  phx-value-deal-id={deal.id}
                  class="trd-notice__act trd-notice__act--black"
                >
                  Доставить
                </button>
                <button
                  :if={default_available?(deal, @character)}
                  id={"trade-default-black-deal-#{deal.id}"}
                  type="button"
                  phx-click="default_black_deal"
                  phx-value-deal-id={deal.id}
                  class="trd-notice__act trd-notice__act--danger"
                >
                  Заявить о срыве
                </button>
              </article>
            </div>
          </section>

          <button
            id="trade-refresh"
            type="button"
            phx-click="refresh"
            class="trd-refresh"
          >
            обновить записи лавочников
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
    |> assign(:black_market_risks, state.black_market_risks)
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

  defp default_available?(deal, character) do
    deal.status == :awaiting_delivery and deal.buyer_character_id == character.id and
      delivery_due?(deal)
  end

  defp delivery_due?(deal) do
    case Map.get(deal.metadata || %{}, "delivery_due_at") do
      due_at when is_binary(due_at) ->
        case DateTime.from_iso8601(due_at) do
          {:ok, parsed, _offset} -> DateTime.compare(DateTime.utc_now(), parsed) != :lt
          _invalid -> true
        end

      _missing ->
        true
    end
  end

  defp delivery_due_label(deal) do
    case Map.get(deal.metadata || %{}, "delivery_due_at") do
      due_at when is_binary(due_at) ->
        case DateTime.from_iso8601(due_at) do
          {:ok, parsed, _offset} -> Calendar.strftime(parsed, "%d.%m %H:%M UTC")
          _invalid -> "не определён"
        end

      _missing ->
        "не определён"
    end
  end

  defp deal_status_label(:awaiting_delivery), do: "ожидает доставки"
  defp deal_status_label(:fulfilled), do: "доставлена"
  defp deal_status_label(:defaulted), do: "сорвана"
  defp deal_status_label(_status), do: "состояние уточняется"

  defp format_bps(bps) when is_integer(bps) do
    :erlang.float_to_binary(bps / 100, decimals: 2) <> "%"
  end

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
