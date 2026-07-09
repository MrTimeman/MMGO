defmodule MMGOWeb.PartyLive do
  @moduledoc """
  Design-pass screen — the party sheet (GDD §13).

  The centrepiece is the single shared HP pool: one bar for the whole
  party, because damage to any member drains the same pool (§3.2). Members
  keep their own fatigue and status. Roles are emergent, hinted per member.

  Interactive demo: loot-rule selector, an invite modal with pending
  invites, and a toggle to review the solo empty state.
  See docs/UI_DESIGN_BRIEF.md.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  @members [
    %{
      name: "Альберт Северин",
      klass: "маг",
      level: 12,
      fatigue: 20,
      leader: true,
      chips: ["Свеж"],
      role: "Заклинатель — урон и контроль внутри Башни. Единственный, кто знает Ритуал Возврата."
    },
    %{
      name: "Гром Железнобородый",
      klass: "мастеровой",
      level: 14,
      fatigue: 55,
      leader: false,
      chips: ["Щитоносец", "Утомлён"],
      role: "Фронтлайн — держит удар и прикрывает магов на дороге, где магия молчит."
    },
    %{
      name: "Лисса Вьюн",
      klass: "алхимик",
      level: 9,
      fatigue: 35,
      leader: false,
      chips: ["Сыта", "Готовит"],
      role: "Зелья и провизия — варит еду из добытого в пути, лечит отряд между схватками."
    },
    %{
      name: "Одо Кузнец",
      klass: "ремесленник",
      level: 11,
      fatigue: 40,
      leader: false,
      chips: ["Ранен"],
      role: "Чинит щиты и снаряжение на привалах. Без него железо тупится и ломается насовсем."
    }
  ]

  @loot_rules [
    %{key: "first", title: "Первый взял", desc: "что нашёл — то твоё; быстро, но сеет раздор."},
    %{key: "round", title: "По кругу", desc: "добыча идёт по очереди — честно и без обид."},
    %{key: "leader", title: "Решает лидер", desc: "вожак делит трофеи по своему усмотрению."}
  ]

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — load the character's real party, HP pool and pending invites.
    {:ok,
     socket
     |> assign(:page_title, "Отряд")
     |> assign(:members, @members)
     |> assign(:party_name, "Вольный отряд")
     |> assign(:hp, 214)
     |> assign(:hp_max, 260)
     |> assign(:loot_rule, "round")
     |> assign(:solo, false)
     |> assign(:invite_open, false)
     |> assign(:pending, [%{name: "Тень Ворона", note: "приглашён · ожидает ответа"}])}
  end

  @impl true
  def handle_event("set_loot", %{"key" => key}, socket) do
    {:noreply, assign(socket, :loot_rule, key)}
  end

  @impl true
  def handle_event("toggle_solo", _params, socket) do
    {:noreply, assign(socket, :solo, not socket.assigns.solo)}
  end

  @impl true
  def handle_event("open_invite", _params, socket) do
    {:noreply, assign(socket, :invite_open, true)}
  end

  @impl true
  def handle_event("close_invite", _params, socket) do
    {:noreply, assign(socket, :invite_open, false)}
  end

  @impl true
  def handle_event("send_invite", %{"name" => name}, socket) do
    # TODO: wire — dispatch a real party invitation to the named character.
    name = String.trim(name)

    socket =
      if name == "" do
        socket
      else
        update(socket, :pending, &[%{name: name, note: "приглашён · ожидает ответа"} | &1])
      end

    {:noreply, assign(socket, :invite_open, false)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:loot_rules, @loot_rules)
      |> assign(:hp_pct, round(assigns.hp / assigns.hp_max * 100))

    ~H"""
    <div class="pty-scene">
      <div class="pty-shell">
        <a href={~p"/map"} class="pty-exit">← На карту</a>

        <header class="pty-banner">
          <span class="pty-banner__crest">◆</span>
          <p class="pty-banner__eyebrow">Отряд</p>
          <h1 class="pty-banner__name">{@party_name}</h1>
        </header>

        <%= if @solo do %>
          <div class="pty-empty">
            <p class="pty-empty__glyph">☾</p>
            <h2 class="pty-empty__title">Вы путешествуете в одиночку</h2>
            <p class="pty-empty__text">
              В глушь и в подземелье в одиночку ходят немногие — и немногие возвращаются.
              Нужен щит на дороге, зелья в схватке и мастеровой, чтобы чинить снаряжение.
            </p>
            <button type="button" class="pty-btn pty-btn--gold" phx-click="open_invite">
              Позвать спутника
            </button>
            <button type="button" class="pty-solo-toggle" phx-click="toggle_solo">
              ← вернуть демо-отряд
            </button>
          </div>
        <% else %>
          <section class="pty-hp">
            <div class="pty-hp__head">
              <span class="pty-hp__title">Общий котёл здоровья</span>
              <span class="pty-hp__num">{@hp} / {@hp_max}</span>
            </div>
            <div class="pty-hp__bar">
              <div class="pty-hp__fill" style={"width:#{@hp_pct}%"}></div>
            </div>
            <p class="pty-hp__note">
              Один пул на весь отряд: урон по любому бойцу опустошает общий котёл (§3.2).
            </p>
          </section>

          <section class="pty-members">
            <article :for={m <- @members} class="pty-card">
              <.art_slot kind="portrait" label={m.name} class="pty-face" />
              <div class="pty-card__body">
                <div class="pty-card__top">
                  <h3 class="pty-card__name">
                    {m.name}
                    <span :if={m.leader} class="pty-card__crown" title="лидер отряда">
                      ✦
                    </span>
                  </h3>
                  <span class="pty-card__lvl">ур. {m.level}</span>
                </div>
                <span class={"pty-card__class pty-card__class--#{m.klass}"}>{m.klass}</span>

                <div class="pty-fat">
                  <span class="pty-fat__label">Утомление</span>
                  <div class="pty-fat__bar">
                    <div
                      class={["pty-fat__fill", m.fatigue >= 50 && "is-high"]}
                      style={"width:#{m.fatigue}%"}
                    >
                    </div>
                  </div>
                </div>

                <div class="pty-card__chips">
                  <span :for={c <- m.chips} class={["pty-tag", tag_mod(c)]}>{c}</span>
                </div>
                <p class="pty-card__role">{m.role}</p>
              </div>
            </article>
          </section>

          <section class="pty-loot">
            <h2 class="pty-loot__title">Дележ добычи</h2>
            <div class="pty-loot__opts">
              <button
                :for={r <- @loot_rules}
                type="button"
                class={"pty-loot__opt#{if @loot_rule == r.key, do: " is-on"}"}
                phx-click="set_loot"
                phx-value-key={r.key}
              >
                {r.title}
              </button>
            </div>
            <p class="pty-loot__desc">
              {Enum.find(@loot_rules, &(&1.key == @loot_rule)).desc}
            </p>
            <p class="pty-loot__xp">
              Опыт всегда делится поровну между участниками события (§13.3). Дележ трофеев —
              на совести отряда: правил нет, предательство возможно.
            </p>
          </section>

          <section class="pty-invite">
            <div class="pty-invite__head">
              <h2 class="pty-invite__title">Приглашения</h2>
              <button type="button" class="pty-btn pty-btn--ghost" phx-click="open_invite">
                + Позвать
              </button>
            </div>
            <ul class="pty-pending">
              <li :for={p <- @pending} class="pty-pending__row">
                <span class="pty-pending__name">{p.name}</span>
                <span class="pty-pending__note">{p.note}</span>
              </li>
              <li :if={@pending == []} class="pty-pending__empty">Открытых приглашений нет.</li>
            </ul>
            <button type="button" class="pty-solo-toggle" phx-click="toggle_solo">
              показать состояние «в одиночку» →
            </button>
          </section>
        <% end %>
      </div>

      <%= if @invite_open do %>
        <div class="pty-modal">
          <div
            class="pty-modal__card"
            phx-click-away="close_invite"
            phx-window-keydown="close_invite"
            phx-key="Escape"
          >
            <p class="pty-modal__eyebrow">Приглашение в отряд</p>
            <h3 class="pty-modal__title">Позвать спутника</h3>
            <form phx-submit="send_invite" class="pty-modal__form">
              <label class="pty-modal__label" for="invite-name">Имя странника</label>
              <input
                id="invite-name"
                name="name"
                type="text"
                autocomplete="off"
                placeholder="напр. Мирра Светлая"
                class="pty-modal__input"
              />
              <div class="pty-modal__row">
                <button type="button" class="pty-btn pty-btn--ghost" phx-click="close_invite">
                  Отмена
                </button>
                <button type="submit" class="pty-btn pty-btn--gold">Отправить</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp tag_mod(chip) when chip in ["Ранен", "Утомлён"], do: "pty-tag--warn"
  defp tag_mod(chip) when chip in ["Свеж", "Сыта"], do: "pty-tag--good"
  defp tag_mod(_chip), do: nil
end
