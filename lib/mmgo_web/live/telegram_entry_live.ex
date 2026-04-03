defmodule MMGOWeb.TelegramEntryLive do
  use MMGOWeb, :live_view

  alias MMGO.Accounts

  @impl true
  def mount(params, session, socket) do
    entry_payload = merge_entry_payload(session, params)
    {:ok, entry} = Accounts.restore_telegram_entry(entry_payload, session: session)

    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> assign(:page_title, "MMGO Entry")
     |> assign(:entry, entry)
     |> assign(:entry_state, entry.state)}
  end

  @impl true
  def handle_event("retry_bootstrap", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section
        id="telegram-entry-live"
        class="overflow-hidden rounded-[2rem] border border-stone-200 bg-white/90 shadow-xl shadow-stone-950/10"
      >
        <div class="grid gap-8 px-6 py-8 sm:px-8 lg:grid-cols-[minmax(0,1.2fr)_22rem] lg:items-start">
          <div class="space-y-6">
            <div class="space-y-3">
              <p class="text-xs font-semibold uppercase tracking-[0.26em] text-amber-900">
                {realm_name(@entry)}
              </p>
              <h1 class="max-w-2xl text-4xl font-semibold tracking-tight text-stone-950 sm:text-5xl">
                {heading_for(@entry_state)}
              </h1>
              <p class="max-w-2xl text-base leading-7 text-stone-700">
                {body_copy_for(@entry_state)}
              </p>
            </div>

            <%= cond do %>
              <% @entry_state == :first_open -> %>
                <section id="entry-first-open" class="space-y-4">
                  <div
                    id="entry-character-preview"
                    class="rounded-[1.75rem] border border-stone-200 bg-stone-950 px-5 py-5 text-stone-100"
                  >
                    <p class="text-xs uppercase tracking-[0.22em] text-amber-300">Character Preview</p>
                    <p class="mt-3 text-2xl font-semibold">{character_name(@entry)}</p>
                    <p class="mt-1 text-sm text-stone-300">{account_name(@entry)}</p>
                  </div>

                  <button
                    id="entry-primary-cta"
                    type="button"
                    class="inline-flex min-h-12 items-center justify-center rounded-full bg-amber-500 px-6 py-3 text-sm font-semibold text-stone-950 transition hover:bg-amber-400"
                  >
                    Enter World
                  </button>
                </section>

              <% @entry_state == :resume -> %>
                <section id="entry-resume" class="space-y-4">
                  <div
                    id="entry-character-preview"
                    class="rounded-[1.75rem] border border-stone-200 bg-stone-950 px-5 py-5 text-stone-100"
                  >
                    <p class="text-xs uppercase tracking-[0.22em] text-amber-300">Returning Adventurer</p>
                    <p class="mt-3 text-2xl font-semibold">{character_name(@entry)}</p>
                    <p class="mt-1 text-sm text-stone-300">{account_name(@entry)}</p>
                  </div>

                  <button
                    id="entry-primary-cta"
                    type="button"
                    class="inline-flex min-h-12 items-center justify-center rounded-full bg-amber-500 px-6 py-3 text-sm font-semibold text-stone-950 transition hover:bg-amber-400"
                  >
                    Resume Journey
                  </button>
                </section>

              <% @entry_state == :deep_link -> %>
                <section id="entry-deep-link" class="space-y-4">
                  <div
                    id="entry-character-preview"
                    class="rounded-[1.75rem] border border-stone-200 bg-stone-950 px-5 py-5 text-stone-100"
                  >
                    <p class="text-xs uppercase tracking-[0.22em] text-amber-300">Linked Return</p>
                    <p class="mt-3 text-2xl font-semibold">{character_name(@entry)}</p>
                    <p class="mt-1 text-sm text-stone-300">Target: {format_target(@entry.target)}</p>
                  </div>

                  <button
                    id="entry-primary-cta"
                    type="button"
                    class="inline-flex min-h-12 items-center justify-center rounded-full bg-amber-500 px-6 py-3 text-sm font-semibold text-stone-950 transition hover:bg-amber-400"
                  >
                    Enter World
                  </button>

                  <%= if @entry.notice do %>
                    <p class="text-sm text-amber-800">{@entry.notice}</p>
                  <% end %>
                </section>

              <% true -> %>
                <section id="entry-recovery" class="space-y-4">
                  <div class="rounded-[1.75rem] border border-red-200 bg-red-50 px-5 py-5">
                    <p class="text-sm font-semibold text-red-800">
                      {recovery_title(@entry)}
                    </p>
                    <p class="mt-2 text-sm leading-6 text-red-700">
                      {recovery_body(@entry)}
                    </p>
                  </div>

                  <div class="flex flex-col gap-3 sm:flex-row">
                    <button
                      id="entry-retry"
                      type="button"
                      phx-click="retry_bootstrap"
                      class="inline-flex min-h-12 items-center justify-center rounded-full bg-stone-950 px-6 py-3 text-sm font-semibold text-white transition hover:bg-black"
                    >
                      Try Telegram Again
                    </button>

                    <a
                      id="entry-bot-fallback"
                      href="https://t.me/mmgo_bot"
                      class="inline-flex min-h-12 items-center justify-center rounded-full border border-stone-300 bg-white px-6 py-3 text-sm font-semibold text-stone-800 transition hover:border-stone-950 hover:text-stone-950"
                    >
                      Open Bot Fallback
                    </a>
                  </div>
                </section>
            <% end %>
          </div>

          <aside class="rounded-[1.75rem] border border-stone-200 bg-stone-100 px-5 py-5">
            <p class="text-xs font-semibold uppercase tracking-[0.24em] text-stone-500">Settings</p>
            <div class="mt-4 grid gap-3">
              <div class="rounded-2xl border border-stone-200 bg-white px-4 py-3 text-sm text-stone-700">
                Sound
              </div>
              <div class="rounded-2xl border border-stone-200 bg-white px-4 py-3 text-sm text-stone-700">
                Language
              </div>
              <div class="rounded-2xl border border-stone-200 bg-white px-4 py-3 text-sm text-stone-700">
                Help
              </div>
            </div>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp heading_for(:first_open), do: "A new realm opens."
  defp heading_for(:resume), do: "Your journey remembers you."
  defp heading_for(:deep_link), do: "A summons awaits."
  defp heading_for(:recovery), do: "The gate lost your trail."

  defp body_copy_for(:first_open),
    do: "Confirm your traveler identity, review your first character, and step into the realm."

  defp body_copy_for(:resume),
    do: "Your account link is intact. Review your character and return to the world without another setup step."

  defp body_copy_for(:deep_link),
    do: "A Telegram prompt brought you back with a specific destination in mind. Continue directly once the gate is clear."

  defp body_copy_for(:recovery),
    do: "MMGO could not match this browser visit to a Telegram identity. Retry from Telegram or reopen the bot fallback."

  defp realm_name(%{realm: %{name: name}}) when is_binary(name), do: name
  defp realm_name(_entry), do: "Canonical Realm"

  defp account_name(%{account: %{display_name: display_name}}) when is_binary(display_name), do: display_name
  defp account_name(_entry), do: "Unknown Traveler"

  defp character_name(%{character: %{name: name}}) when is_binary(name), do: name
  defp character_name(_entry), do: "Unbound Wanderer"

  defp recovery_title(%{recovery: %{title: title}}) when is_binary(title), do: title
  defp recovery_title(_entry), do: "We couldn't restore your traveler seal."

  defp recovery_body(%{recovery: %{body: body}}) when is_binary(body), do: body
  defp recovery_body(_entry), do: "Try again from Telegram, or reopen MMGO from the bot to refresh your link."

  defp format_target(target) when is_binary(target), do: target
  defp format_target(target) when is_map(target), do: Map.get(target, :label) || Map.get(target, "label") || Map.get(target, "target") || "linked destination"
  defp format_target(_target), do: "linked destination"

  defp merge_entry_payload(session, params) when is_map(params) do
    session
    |> Map.get("telegram_entry", %{})
    |> Map.merge(params)
  end

  defp merge_entry_payload(session, _params) do
    Map.get(session, "telegram_entry", %{})
  end

end
