defmodule MMGOWeb.FinanceLive do
  @moduledoc """
  Scoped balance, ledger, charity, and tuition surface.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket),
    do: load_finance(socket, socket.assigns.current_scope.character)

  @impl true
  def handle_event("donate", %{"donation" => %{"amount" => amount}}, socket) do
    submit_amount(socket, amount, &Play.donate_to_charity/2, "Пожертвование внесено в фонд.")
  end

  @impl true
  def handle_event("pay_tuition", %{"tuition" => %{"amount" => amount}}, socket) do
    submit_amount(
      socket,
      amount,
      &Play.pay_academy_tuition/2,
      "Плата за обучение перечислена в казну."
    )
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_finance(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="finance-screen" class="scene-desk fin-scene">
        <div class="book fin-book">
          <div class="book__spine"></div>
          <div class="book__page">
            <div class="book__ribbons" aria-hidden="true">
              <span class="book__ribbon book__ribbon--active">Счета</span>
              <span class="book__ribbon">Записи</span>
            </div>

            <.link id="finance-back-to-map" navigate={~p"/map"} class="book__back">
              ← закрыть книгу
            </.link>

            <div class="book__leaf">
              <header class="fin-masthead">
                <p class="fin-masthead__eyebrow">счётная книга · {@location.name}</p>
                <h1 class="book__title">Финансы {@character.name}</h1>
                <p class="book__subtitle">приход, расход и обязательства — без пропущенной монеты</p>
              </header>

              <div id="finance-balance" class="fin-balance">
                <span class="fin-balance__label">В кошеле и на счету</span>
                <span class="fin-balance__sum">
                  <span class="fin-coin">◈</span>{@balance}
                </span>
                <span class="fin-balance__unit">монет княжества</span>
              </div>

              <div :if={@error} id="finance-error" class="fin-ink-error">
                {@error}
              </div>

              <section id="finance-public-accounts" class="fin-flow">
                <article class="fin-flow__col fin-flow__col--treasury">
                  <span class="fin-flow__label">Казна королевства</span>
                  <strong class="fin-flow__amt">{@treasury_balance}</strong>
                  <span class="fin-flow__unit">◈ открытого счёта</span>
                </article>
                <article class="fin-flow__col fin-flow__col--charity">
                  <span class="fin-flow__label">Фонд Просвещения</span>
                  <strong class="fin-flow__amt">{@charity_balance}</strong>
                  <span class="fin-flow__unit">◈ для учеников</span>
                </article>
              </section>

              <section id="finance-actions" class="fin-actions">
                <.form
                  for={@donation_form}
                  id="finance-donation-form"
                  phx-submit="donate"
                  class="fin-charity fin-action"
                >
                  <span class="fin-action__mark" aria-hidden="true">✦</span>
                  <h2 class="fin-h">Пожертвование</h2>
                  <p class="fin-charity__note">
                    «Ваш взнос учит того, кому нечем платить за науку.»
                  </p>
                  <.input
                    field={@donation_form[:amount]}
                    type="number"
                    label="Сумма"
                    min="1"
                    inputmode="numeric"
                  />
                  <button id="finance-donate" type="submit" class="fin-charity__btn">
                    Внести в фонд
                  </button>
                </.form>

                <.form
                  for={@tuition_form}
                  id="finance-tuition-form"
                  phx-submit="pay_tuition"
                  class="fin-action fin-action--tuition"
                >
                  <span class="fin-action__mark" aria-hidden="true">A</span>
                  <h2 class="fin-h">Академическая пошлина</h2>
                  <p class="fin-action__copy">
                    Плата за обучение перечисляется прямо в казну и получает отдельную строку в
                    книге.
                  </p>
                  <.input
                    field={@tuition_form[:amount]}
                    type="number"
                    label="Сумма"
                    min="1"
                    inputmode="numeric"
                  />
                  <button id="finance-pay-tuition" type="submit" class="fin-action__btn">
                    Поставить платёж
                  </button>
                </.form>
              </section>

              <section id="finance-ledger" class="fin-ledger-sheet">
                <div class="fin-ledger-sheet__head">
                  <div>
                    <p class="fin-ledger-sheet__eyebrow">последние строки</p>
                    <h2 class="fin-h">Журнал операций</h2>
                  </div>
                  <span class="fin-ledger-sheet__quill" aria-hidden="true">✒</span>
                </div>
                <p :if={@ledger_entries == []} id="finance-ledger-empty" class="fin-margin">
                  В журнале пока нет операций.
                </p>
                <ul class="fin-plain fin-plain--ledger">
                  <li class="fin-plain__header" aria-hidden="true">
                    <span>Статья</span><span>Дата</span><span>Сумма</span>
                  </li>
                  <li
                    :for={entry <- @ledger_entries}
                    id={"finance-entry-#{entry.id}"}
                    class="fin-plain__row"
                  >
                    <span class="fin-plain__what">{entry.entry_type}</span>
                    <time class="fin-plain__date">{format_time(entry.inserted_at)}</time>
                    <span class="fin-plain__amt">{entry.amount} ◈</span>
                  </li>
                </ul>
                <p class="fin-margin">сверено рукою казначея</p>
              </section>

              <div class="fin-book__foot">
                <span>Лист обновляется после каждой подтверждённой операции.</span>
                <button id="finance-refresh" type="button" phx-click="refresh">
                  обновить чернила
                </button>
              </div>
            </div>
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp submit_amount(socket, amount, command, message) do
    with {:ok, value} <- parse_positive(amount),
         {:ok, _state} <- command.(socket.assigns.character, value) do
      {:noreply, socket |> put_flash(:info, message) |> refresh_finance()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  defp load_finance(socket, character) do
    case Play.finance_state(character) do
      {:ok, state} ->
        {:ok,
         socket |> assign(:page_title, "Финансы") |> assign(:error, nil) |> assign_finance(state)}

      {:error, :travelling} ->
        {:ok, push_navigate(socket, to: ~p"/travel")}

      {:error, _reason} ->
        {:ok, push_navigate(socket, to: ~p"/map")}
    end
  end

  defp refresh_finance(socket) do
    case Play.finance_state(socket.assigns.character) do
      {:ok, state} -> socket |> assign(:error, nil) |> assign_finance(state)
      {:error, :travelling} -> push_navigate(socket, to: ~p"/travel")
      {:error, _reason} -> assign(socket, :error, "Счётная книга сейчас недоступна.")
    end
  end

  defp assign_finance(socket, state) do
    socket
    |> assign(:character, state.character)
    |> assign(:location, state.location)
    |> assign(:balance, state.balance)
    |> assign(:ledger_entries, state.ledger_entries)
    |> assign(:treasury_balance, state.treasury_balance)
    |> assign(:charity_balance, state.charity_balance)
    |> assign(:donation_form, to_form(%{"amount" => ""}, as: :donation))
    |> assign(:tuition_form, to_form(%{"amount" => ""}, as: :tuition))
  end

  defp parse_positive(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _other -> {:error, :invalid_amount}
    end
  end

  defp parse_positive(_value), do: {:error, :invalid_amount}
  defp format_time(time), do: Calendar.strftime(time, "%d.%m %H:%M")
  defp error_message(:invalid_amount), do: "Укажите положительную сумму."
  defp error_message(_reason), do: "Операция не выполнена: проверьте баланс."
end
