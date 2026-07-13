defmodule MMGOWeb.NotificationsLive do
  @moduledoc """
  Scoped in-world delivery history for the current character.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Вести")
     |> refresh_notifications()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_notifications(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="notifications-screen" class="min-h-full bg-stone-950 px-4 py-8 text-stone-100">
        <div class="mx-auto w-full max-w-4xl space-y-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.link
              id="notifications-back-map"
              navigate={~p"/map"}
              class="text-sm text-sky-200 underline decoration-sky-500/40 underline-offset-4"
            >
              ← Карта мира
            </.link>
            <button
              id="notifications-refresh"
              type="button"
              phx-click="refresh"
              class="rounded border border-stone-600 px-3 py-2 text-sm text-stone-200 transition hover:border-stone-400"
            >
              Обновить
            </button>
          </div>

          <header class="rounded-2xl border border-sky-400/25 bg-gradient-to-br from-slate-900 via-stone-950 to-sky-950/30 p-7 shadow-2xl">
            <p class="text-xs uppercase tracking-[0.25em] text-sky-200/75">личный архив</p>
            <h1 class="mt-2 font-serif text-3xl text-sky-100">Вести и доставки</h1>
            <p class="mt-3 max-w-2xl text-sm leading-6 text-stone-300">
              Здесь остаются только ваши записи: ожидающие, доставленные и неудачные сообщения Telegram.
            </p>
          </header>

          <section id="notification-history" class="space-y-3">
            <article
              :if={@state.notifications == []}
              id="notifications-empty"
              class="rounded-2xl border border-stone-700 bg-stone-900/80 p-6 text-sm text-stone-400 shadow-lg"
            >
              Писарь ещё не принёс ни одной вести.
            </article>

            <article
              :for={notification <- @state.notifications}
              id={"notification-#{notification.id}"}
              class="rounded-2xl border border-stone-700 bg-stone-900/80 p-5 shadow-lg"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p class="text-xs uppercase tracking-[0.18em] text-stone-500">
                    {kind_label(notification.kind)} · {channel_label(notification.channel)}
                  </p>
                  <h2 class="mt-1 font-serif text-xl text-stone-100">
                    {kind_label(notification.kind)}
                  </h2>
                </div>
                <span
                  id={"notification-status-#{notification.id}"}
                  class={[
                    "rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.12em]",
                    status_class(notification.status)
                  ]}
                >
                  {status_label(notification.status)}
                </span>
              </div>

              <dl class="mt-4 grid gap-3 text-sm sm:grid-cols-3">
                <div>
                  <dt class="text-stone-500">Поставлено</dt>
                  <dd class="mt-1 text-stone-200">{format_time(notification.scheduled_at)}</dd>
                </div>
                <div>
                  <dt class="text-stone-500">Доставлено</dt>
                  <dd class="mt-1 text-stone-200">{format_time(notification.delivered_at)}</dd>
                </div>
                <div>
                  <dt class="text-stone-500">Канал</dt>
                  <dd class="mt-1 text-stone-200">{channel_label(notification.channel)}</dd>
                </div>
              </dl>

              <p class="mt-4 border-t border-stone-700 pt-4 text-sm leading-6 text-stone-300">
                {payload_summary(notification.payload)}
              </p>

              <p
                :if={notification.error}
                id={"notification-error-#{notification.id}"}
                class="mt-3 rounded-lg border border-rose-400/35 bg-rose-950/25 px-3 py-2 text-sm text-rose-100"
              >
                {notification.error}
              </p>
            </article>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp refresh_notifications(socket) do
    case Play.notifications_state(socket.assigns.current_scope.character) do
      {:ok, state} ->
        assign(socket, :state, state)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Не удалось прочитать архив вестей.")
        |> push_navigate(to: ~p"/map")
    end
  end

  defp kind_label("journey_arrived"), do: "Прибытие"
  defp kind_label("scavenge_completed"), do: "Поиск ресурсов"
  defp kind_label("academy_completed"), do: "Академия"
  defp kind_label("research_completed"), do: "Исследование"
  defp kind_label("party_invitation"), do: "Приглашение в отряд"
  defp kind_label("club_invitation"), do: "Клубное приглашение"
  defp kind_label("org_invitation"), do: "Приглашение организации"

  defp kind_label(kind),
    do: kind |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp channel_label(:telegram), do: "Telegram"
  defp channel_label(:in_app), do: "в приложении"
  defp channel_label(channel), do: to_string(channel)

  defp status_label(:pending), do: "ожидает"
  defp status_label(:sent), do: "доставлено"
  defp status_label(:failed), do: "ошибка"
  defp status_label(:discarded), do: "отменено"
  defp status_label(status), do: to_string(status)

  defp status_class(:sent), do: "border-emerald-300/45 bg-emerald-950/35 text-emerald-100"
  defp status_class(:failed), do: "border-rose-300/45 bg-rose-950/35 text-rose-100"
  defp status_class(:discarded), do: "border-stone-500/45 bg-stone-800 text-stone-200"
  defp status_class(_status), do: "border-amber-300/45 bg-amber-950/35 text-amber-100"

  defp payload_summary(payload) when is_map(payload) and map_size(payload) > 0 do
    payload
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join(" · ", fn {key, value} -> "#{key}: #{payload_value(value)}" end)
  end

  defp payload_summary(_payload), do: "Письмо не содержит дополнительных сведений."

  defp payload_value(value) when is_binary(value) or is_integer(value), do: to_string(value)
  defp payload_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp payload_value(true), do: "да"
  defp payload_value(false), do: "нет"
  defp payload_value(_value), do: "записано"

  defp format_time(%DateTime{} = time), do: Calendar.strftime(time, "%d.%m · %H:%M UTC")
  defp format_time(_time), do: "—"
end
