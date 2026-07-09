defmodule MMGOWeb.DefeatLive do
  @moduledoc """
  Roguelike's Sacrifice (GDD §10.5) — the death-and-revival moment. When a
  party's shared HP hits zero, everyone is returned to the Tower entrance;
  all carried loot and grimoires are lost, but the run's XP is kept. The
  sting is economic, not existential — so this screen is solemn and hopeful,
  never punishing.

  Design-pass screen: hardcoded demo ledger, no backend.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  # TODO: wire — the real ledger comes from the resolved combat: what the
  # party was carrying at death, which grimoire was brought, XP accrued.
  @lost_loot [
    %{name: "Пепельный самоцвет", qty: 2, note: "редкий реагент"},
    %{name: "Кристалл маны", qty: 1, note: "почти чистый"},
    %{name: "Свиток забытой школы", qty: 1, note: "не прочитан"},
    %{name: "Клык матки", qty: 3, note: "трофей с третьего яруса"}
  ]
  @lost_coins 340
  @lost_grimoire "Малый гримуар «Искра» — 8 заклинаний"
  @kept_xp 1_240

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Жертва Роглайка")
     |> assign(:lost_loot, @lost_loot)
     |> assign(:lost_coins, @lost_coins)
     |> assign(:lost_grimoire, @lost_grimoire)
     |> assign(:kept_xp, @kept_xp)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dft-hall">
      <div class="dft-vignette"></div>

      <div class="dft-scroll">
        <div class="dft-scene">
          <.art_slot
            kind="hero"
            label="Врата Башни на рассвете — возвращение павших"
            variant="dark"
          />
        </div>

        <header class="dft-head">
          <p class="dft-kicker">Жертва Роглайка</p>
          <h1 class="dft-title">Жертва Роглайка вернула вас к вратам Башни.</h1>
          <p class="dft-verse">
            Ни одна душа не остаётся в глубине. Плоть возвращается на порог, откуда сошла, —
            но всё, что руки несли из тьмы, тьме и остаётся.
          </p>
        </header>

        <%!-- The funeral ledger: what the dark kept ── --%>
        <section class="dft-ledger">
          <div class="dft-ledger__band dft-ledger__band--lost">
            <span class="dft-ledger__glyph">☒</span>
            <span class="dft-ledger__band-title">Оставлено во тьме</span>
          </div>

          <ul class="dft-loot">
            <%= for item <- @lost_loot do %>
              <li class="dft-loot__row">
                <span class="dft-loot__name">{item.name}</span>
                <span class="dft-loot__note">{item.note}</span>
                <span class="dft-loot__qty">×{item.qty}</span>
              </li>
            <% end %>
            <li class="dft-loot__row dft-loot__row--grim">
              <span class="dft-loot__name">{@lost_grimoire}</span>
              <span class="dft-loot__note">книга — предмет, не память</span>
              <span class="dft-loot__qty">утрачен</span>
            </li>
            <li class="dft-loot__row dft-loot__row--coins">
              <span class="dft-loot__name">Монеты</span>
              <span class="dft-loot__note">выпали на месте гибели</span>
              <span class="dft-loot__qty">{@lost_coins}</span>
            </li>
          </ul>

          <div class="dft-kept">
            <div class="dft-kept__band">
              <span class="dft-kept__glyph">✦</span>
              <span class="dft-kept__band-title">Сохранено</span>
            </div>
            <div class="dft-kept__body">
              <p class="dft-kept__label">Опыт, добытый в глубине</p>
              <p class="dft-kept__value">+{@kept_xp} XP</p>
              <p class="dft-kept__aside">
                Потеряны вещи — не путь. То, чему вы научились под Башней, остаётся с вами.
              </p>
            </div>
          </div>
        </section>

        <footer class="dft-foot">
          <a href={~p"/map"} class="dft-continue">Ступить за порог</a>
          <a href={~p"/combat"} class="dft-avenge">
            <span class="dft-avenge__glyph">⚔</span> Отомстить
          </a>
        </footer>
      </div>
    </div>
    """
  end
end
