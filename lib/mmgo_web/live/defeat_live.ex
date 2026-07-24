defmodule MMGOWeb.DefeatLive do
  @moduledoc """
  The persisted Roguelike's Sacrifice ledger for a failed dungeon run.
  """
  use MMGOWeb, :live_view

  alias MMGO.Play

  @impl true
  def mount(_params, _session, socket) do
    case Play.defeat_state(socket.assigns.current_scope.character) do
      {:ok, state} ->
        {:ok, socket |> assign(:page_title, "Жертва Роглайка") |> assign(:state, state)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:info, "Нет недавней жертвы, которую можно показать.")
         |> push_navigate(to: ~p"/map")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} game_nav={false}>
      <main id="defeat-screen" class="min-h-full bg-stone-950 px-4 py-10 text-stone-100">
        <div class="mx-auto w-full max-w-3xl space-y-6">
          <header class="rounded-2xl border border-violet-400/25 bg-gradient-to-br from-violet-950/45 via-stone-950 to-stone-900 p-7 shadow-2xl">
            <p class="text-xs uppercase tracking-[0.28em] text-violet-200/75">Жертва Роглайка</p>
            <h1 class="mt-2 font-serif text-3xl text-violet-100">Вы возвращены к вратам.</h1>
            <p class="mt-3 max-w-2xl text-sm leading-6 text-stone-300">
              Жертва удержала путь для {@state.character.name}: предметы остались там, где пал отряд, но добытый опыт не исчез.
            </p>
          </header>

          <section
            id="defeat-ledger"
            class="rounded-2xl border border-rose-400/25 bg-rose-950/20 p-6 shadow-lg"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-3">
              <div>
                <p class="text-xs uppercase tracking-[0.2em] text-rose-200/75">оставлено во тьме</p>
                <h2 class="mt-1 font-serif text-2xl text-rose-100">Потерянное снаряжение</h2>
              </div>
              <span id="defeat-run-id" class="font-mono text-xs text-stone-500">
                поход {@state.run.id}
              </span>
            </div>

            <p :if={@state.lost_drops == []} id="defeat-no-drops" class="mt-4 text-sm text-stone-400">
              В записях этого похода нет переносимых предметов.
            </p>
            <ul :if={@state.lost_drops != []} id="defeat-drops" class="mt-4 space-y-2">
              <li
                :for={drop <- @state.lost_drops}
                id={"defeat-drop-#{drop.id}"}
                class="flex items-center justify-between rounded-lg border border-rose-300/15 bg-stone-950/55 px-4 py-3 text-sm"
              >
                <span>{drop.name}</span>
                <span class="text-rose-200">{drop_label(drop)}</span>
              </li>
            </ul>
          </section>

          <section
            id="defeat-kept"
            class="rounded-2xl border border-emerald-400/20 bg-emerald-950/15 p-6 shadow-lg"
          >
            <p class="text-xs uppercase tracking-[0.2em] text-emerald-200/75">сохранено</p>
            <p id="defeat-kept-xp" class="mt-2 font-serif text-4xl text-emerald-100">
              +{@state.kept_xp} XP
            </p>
            <p class="mt-2 text-sm leading-6 text-stone-300">
              Опыт за завершённые встречи этого похода уже принадлежит вам.
            </p>
          </section>

          <footer class="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-stone-700 bg-stone-900/80 p-5">
            <p id="defeat-return-location" class="text-sm text-stone-300">
              Возвращение: {@state.return_location.name}
            </p>
            <.link
              id="defeat-return-map"
              navigate={~p"/map"}
              class="rounded-lg bg-violet-300 px-4 py-3 text-sm font-semibold text-stone-950 hover:bg-violet-200"
            >
              Ступить за порог
            </.link>
          </footer>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp drop_label(%{drop_kind: :grimoire}), do: "гримуар · утрачен"
  defp drop_label(drop), do: "×#{drop.quantity}"
end
