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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="defeat-screen" class="dft-hall">
        <div class="dft-vignette"></div>

        <div class="dft-scroll">
          <div class="dft-scene dft-scene--gate" aria-hidden="true">
            <span class="dft-gate__arch"></span>
            <span class="dft-gate__light"></span>
            <span class="dft-gate__road"></span>
          </div>

          <header class="dft-head">
            <p class="dft-kicker">Жертва Роглайка</p>
            <h1 class="dft-title">Вы возвращены к вратам.</h1>
            <p class="dft-verse">
              Жертва удержала путь для {@state.character.name}. Всё, что руки несли из тьмы,
              осталось там; но добытый опыт тьма забрать не смогла.
            </p>
          </header>

          <section id="defeat-ledger" class="dft-ledger">
            <div class="dft-ledger__band dft-ledger__band--lost">
              <span class="dft-ledger__glyph">☒</span>
              <span class="dft-ledger__band-title">Оставлено во тьме</span>
              <span id="defeat-run-id" class="dft-ledger__run">поход {@state.run.id}</span>
            </div>

            <p :if={@state.lost_drops == []} id="defeat-no-drops" class="dft-loot__empty">
              В записях этого похода нет переносимых предметов.
            </p>
            <ul :if={@state.lost_drops != []} id="defeat-drops" class="dft-loot">
              <li
                :for={drop <- @state.lost_drops}
                id={"defeat-drop-#{drop.id}"}
                class={[
                  "dft-loot__row",
                  drop.drop_kind == :grimoire && "dft-loot__row--grim"
                ]}
              >
                <span class="dft-loot__name">{drop.name}</span>
                <span class="dft-loot__note">{drop_note(drop)}</span>
                <span class="dft-loot__qty">{drop_label(drop)}</span>
              </li>
            </ul>

            <section id="defeat-kept" class="dft-kept">
              <div class="dft-kept__band">
                <span class="dft-kept__glyph">✦</span>
                <span class="dft-kept__band-title">Сохранено</span>
              </div>
              <div class="dft-kept__body">
                <p class="dft-kept__label">Опыт, добытый в глубине</p>
                <p id="defeat-kept-xp" class="dft-kept__value">+{@state.kept_xp} опыта</p>
                <p class="dft-kept__aside">
                  Потеряны вещи — не путь. Всё, чему вы научились под Башней, остаётся с вами.
                </p>
              </div>
            </section>
          </section>

          <footer class="dft-foot">
            <p id="defeat-return-location" class="dft-return">
              Возвращение · {@state.return_location.name}
            </p>
            <.link id="defeat-return-map" navigate={~p"/map"} class="dft-continue">
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

  defp drop_note(%{drop_kind: :grimoire}), do: "книга — предмет, не память"
  defp drop_note(_drop), do: "осталось на месте гибели"
end
