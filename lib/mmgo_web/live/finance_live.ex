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
      <main id="finance-screen" class="game-root min-h-full px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-5">
          <.link id="finance-back-to-map" navigate={~p"/map"} class="map-back-link">
            ← Карта мира
          </.link>
          <header class="rounded-xl border border-amber-500/25 bg-stone-900/80 p-6 shadow-xl">
            <p class="text-xs uppercase tracking-[0.22em] text-amber-300/70">
              счётная книга · {@location.name}
            </p>
            <h1 class="mt-2 font-serif text-3xl text-amber-100">Финансы</h1>
            <p id="finance-balance" class="mt-3 text-lg text-amber-100">Ваш кошелёк: {@balance} ◈</p>
          </header>

          <div
            :if={@error}
            id="finance-error"
            class="rounded-md border border-red-500/50 bg-red-950/30 px-4 py-3 text-sm text-red-200"
          >
            {@error}
          </div>

          <section id="finance-public-accounts" class="grid gap-3 sm:grid-cols-2">
            <article class="rounded-xl border border-stone-700 bg-stone-900/70 p-5">
              <p class="text-sm text-stone-400">Казна королевства</p>
              <p class="mt-1 font-serif text-2xl text-stone-100">{@treasury_balance} ◈</p>
            </article>
            <article class="rounded-xl border border-stone-700 bg-stone-900/70 p-5">
              <p class="text-sm text-stone-400">Благотворительный фонд</p>
              <p class="mt-1 font-serif text-2xl text-stone-100">{@charity_balance} ◈</p>
            </article>
          </section>

          <section
            id="finance-actions"
            class="grid gap-5 rounded-xl border border-amber-500/25 bg-amber-950/15 p-6 md:grid-cols-2"
          >
            <.form for={@donation_form} id="finance-donation-form" phx-submit="donate">
              <h2 class="font-serif text-xl text-amber-100">Пожертвовать</h2>
              <p class="mt-1 text-sm text-stone-400">
                Деньги уходят в отдельный фонд и остаются в журнале.
              </p>
              <.input
                field={@donation_form[:amount]}
                type="number"
                label="Сумма"
                min="1"
                inputmode="numeric"
              />
              <button
                id="finance-donate"
                type="submit"
                class="rounded-md bg-amber-300 px-4 py-2 font-semibold text-stone-950 hover:bg-amber-200"
              >
                Внести
              </button>
            </.form>
            <.form for={@tuition_form} id="finance-tuition-form" phx-submit="pay_tuition">
              <h2 class="font-serif text-xl text-amber-100">Оплатить обучение</h2>
              <p class="mt-1 text-sm text-stone-400">Плата перечисляется напрямую в казну.</p>
              <.input
                field={@tuition_form[:amount]}
                type="number"
                label="Сумма"
                min="1"
                inputmode="numeric"
              />
              <button
                id="finance-pay-tuition"
                type="submit"
                class="rounded-md border border-amber-300/60 px-4 py-2 font-semibold text-amber-100 hover:bg-amber-300/10"
              >
                Оплатить
              </button>
            </.form>
          </section>

          <section id="finance-ledger" class="rounded-xl border border-stone-700 bg-stone-900/70 p-6">
            <h2 class="font-serif text-xl text-stone-100">Ваш журнал операций</h2>
            <p
              :if={@ledger_entries == []}
              id="finance-ledger-empty"
              class="mt-3 text-sm text-stone-400"
            >
              В журнале пока нет операций.
            </p>
            <ul class="mt-3 space-y-2">
              <li
                :for={entry <- @ledger_entries}
                id={"finance-entry-#{entry.id}"}
                class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-stone-700 bg-stone-950/45 p-3 text-sm"
              >
                <span>{entry.entry_type}</span><span>{entry.amount} ◈</span><span class="text-stone-500">{format_time(entry.inserted_at)}</span>
              </li>
            </ul>
          </section>

          <button
            id="finance-refresh"
            type="button"
            phx-click="refresh"
            class="text-sm text-amber-200 underline decoration-amber-500/40 underline-offset-4"
          >
            Обновить журнал
          </button>
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
