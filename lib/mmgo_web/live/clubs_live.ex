defmodule MMGOWeb.ClubsLive do
  @moduledoc """
  Design-pass screen family for Academy clubs (GDD §9.8).

  Demo-only: no backend wiring. Routes:
    * /academy/clubs
    * /academy/clubs/:id
    * /academy/clubs/:id/manage
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  @clubs [
    %{
      id: "duelists",
      sigil: "⚔",
      title: "Клуб рассветных дуэлей",
      type: "дуэльный",
      members: 18,
      joined?: true,
      next: "Турнир без ставок · сегодня в сумерках",
      fee: "взнос основателя 120 монет",
      color: "linear-gradient(135deg, #5b211b, #a9791f)"
    },
    %{
      id: "lore",
      sigil: "☙",
      title: "Круг преданий Эленвира",
      type: "общий",
      members: 31,
      joined?: false,
      next: "Чтение хроник · завтра",
      fee: "взнос основателя 80 монет",
      color: "linear-gradient(135deg, #2f3f2c, #8a6f4d)"
    },
    %{
      id: "research",
      sigil: "✎",
      title: "Общество живых печатей",
      type: "исследовательский",
      members: 12,
      joined?: false,
      next: "Общие заметки по Life ward · через 2 дня",
      fee: "взнос основателя 150 монет",
      color: "linear-gradient(135deg, #18384b, #7ecbff)"
    },
    %{
      id: "expedition",
      sigil: "◇",
      title: "Экспедиционный стол",
      type: "экспедиционный",
      members: 24,
      joined?: false,
      next: "Разбор карты подземелья · через 3 дня",
      fee: "взнос основателя 100 монет",
      color: "linear-gradient(135deg, #3a2f24, #7fae6b)"
    }
  ]

  @ladder [
    %{rank: 1, name: "Мира Дол", wins: 9, losses: 1},
    %{rank: 2, name: "Альберт Северин", wins: 7, losses: 2, me?: true},
    %{rank: 3, name: "Каэль Вейн", wins: 6, losses: 3},
    %{rank: 4, name: "Селина Ров", wins: 5, losses: 4}
  ]

  @members ["АС", "МД", "КВ", "СР", "ОВ", "ТИ", "ЛН", "РК"]
  @approvals ["Леон Равнин", "Эльга Хмель", "Никта Соль"]

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — load clubs, membership and president rights for the character.
    {:ok,
     socket
     |> assign(:page_title, "Клубы Академии")
     |> assign(:clubs, @clubs)
     |> assign(:ladder, @ladder)
     |> assign(:members, @members)
     |> assign(:approvals, @approvals)
     |> assign(:joined_event, false)
     |> assign(:scheduled, false)
     |> assign(:accent, "gold")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    club = Enum.find(@clubs, &(&1.id == params["id"])) || hd(@clubs)
    {:noreply, assign(socket, :club, club)}
  end

  @impl true
  def handle_event("join_event", _params, socket) do
    {:noreply, assign(socket, :joined_event, true)}
  end

  @impl true
  def handle_event("schedule", _params, socket) do
    {:noreply, assign(socket, :scheduled, true)}
  end

  @impl true
  def handle_event("accent", %{"tone" => tone}, socket) do
    {:noreply, assign(socket, :accent, tone)}
  end

  @impl true
  def render(%{live_action: :show} = assigns), do: club_show(assigns)
  def render(%{live_action: :manage} = assigns), do: manage(assigns)
  def render(assigns), do: index(assigns)

  defp index(assigns) do
    ~H"""
    <div class="acd-screen">
      <div class="acd-shell">
        <a href={~p"/academy"} class="acd-exit">← В холл</a>

        <div class="acd-hero">
          <.art_slot
            kind="banner"
            label="Академия — клубная ярмарка во внутреннем дворе"
          />
          <div class="acd-hero__veil"></div>
          <div class="acd-hero__cap">
            <p class="acd-eyebrow">Клубное окно · §9.8</p>
            <h1 class="acd-hero__title">Ярмарка клубов</h1>
            <p class="acd-hero__sub">одно посещение в термин открывает стипендии и рейтинги</p>
          </div>
        </div>

        <div class="acd-body">
          <section class="acd-card">
            <p class="acd-card__title">Как основать клуб</p>
            <p class="acd-card__meta">
              Студент Academy Core или профессор платит малый взнос, выбирает устав и сохраняет
              клуб после выпуска. Это мягкое обучение будущим организациям.
            </p>
          </section>

          <section class="acd-section">
            <div class="acd-section__head">
              <h2 class="acd-section__title">Четыре круга студенческой жизни</h2>
              <span class="acd-section__label">
                общие · дуэльные · исследовательские · экспедиционные
              </span>
            </div>

            <div class="acd-club-grid">
              <.link :for={club <- @clubs} navigate={~p"/academy/clubs/#{club.id}"} class="acd-club">
                <span class="acd-club__sigil" style={"background: #{club.color};"}>{club.sigil}</span>
                <span class="acd-club__type">{club.type}</span>
                <span class="acd-club__t">{club.title}</span>
                <span class="acd-card__meta">{club.next}</span>
                <span class="acd-club__foot">
                  <span>{club.members} участников</span>
                  <span class={["acd-badge", club.joined? && "acd-badge--pass"]}>
                    {if club.joined?, do: "состоите", else: "можно вступить"}
                  </span>
                </span>
                <span class="acd-card__meta">{club.fee}</span>
              </.link>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end

  defp club_show(assigns) do
    ~H"""
    <div class="acd-screen">
      <div class="acd-shell">
        <a href={~p"/academy/clubs"} class="acd-exit">← К ярмарке</a>

        <div class="acd-hero acd-banner">
          <.art_slot
            kind="banner"
            label="Клуб рассветных дуэлей — зал с тренировочным кругом"
          />
          <div class="acd-hero__veil"></div>
          <div class="acd-hero__cap">
            <p class="acd-eyebrow">Дуэльный клуб · без ставок и добычи</p>
            <h1 class="acd-hero__title">{@club.title}</h1>
            <p class="acd-hero__sub">лестница побед семестра, дружеский бой, престиж курса</p>
          </div>
        </div>

        <div class="acd-body">
          <section class="acd-card">
            <div class="acd-section__head">
              <p class="acd-card__title" style="margin:0;">Следующее событие</p>
              <span class="acd-badge acd-badge--distinction">сегодня</span>
            </div>
            <p class="acd-card__meta">
              Турнир на рассвете: три коротких поединка, смерть бескровна, чат партии закрыт.
              Победа даст +престиж и строку в клубной летописи.
            </p>
            <button
              type="button"
              class={[
                "acd-btn acd-btn--block",
                @joined_event && "acd-btn--on",
                !@joined_event && "acd-btn--primary"
              ]}
              phx-click="join_event"
            >
              {if @joined_event, do: "Вы внесены в список дуэлянтов", else: "Записаться на турнир"}
            </button>
          </section>

          <section class="acd-section">
            <div class="acd-section__head">
              <h2 class="acd-section__title">Лестница семестра</h2>
              <span class="acd-section__aside">честь без крови</span>
            </div>
            <table class="acd-ladder-tbl">
              <thead>
                <tr>
                  <th>Ранг</th>
                  <th>Участник</th>
                  <th>Победы</th>
                  <th>Поражения</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @ladder} class={Map.get(row, :me?) && "acd-me"}>
                  <td class="acd-num">{row.rank}</td>
                  <td>{row.name}</td>
                  <td class="acd-num">{row.wins}</td>
                  <td class="acd-num">{row.losses}</td>
                </tr>
              </tbody>
            </table>
          </section>

          <section class="acd-card">
            <p class="acd-card__title">Казна клуба</p>
            <div class="acd-treasury">
              <span>на аренду круга и знаки победителей</span>
              <span class="acd-treasury__num">640 ◈</span>
            </div>
          </section>

          <section class="acd-card">
            <p class="acd-card__title">Участники</p>
            <div class="acd-chips">
              <span :for={member <- @members} class="acd-chip">
                <span class="acd-chip__av">{member}</span> студент
              </span>
            </div>
          </section>

          <.link navigate={~p"/academy/clubs/#{@club.id}/manage"} class="acd-btn acd-btn--block">
            Панель президента
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp manage(assigns) do
    ~H"""
    <div class="acd-screen">
      <div class="acd-shell">
        <a href={~p"/academy/clubs/#{@club.id}"} class="acd-exit">← К клубу</a>

        <div class="acd-hero">
          <.art_slot
            kind="banner"
            label="Клубная канцелярия — стол президента"
          />
          <div class="acd-hero__veil"></div>
          <div class="acd-hero__cap">
            <p class="acd-eyebrow">Президентская панель</p>
            <h1 class="acd-hero__title">Управление клубом</h1>
            <p class="acd-hero__sub">лёгкая версия организаций: события, роли, знак и казна</p>
          </div>
        </div>

        <div class="acd-body">
          <section class="acd-card">
            <p class="acd-card__title">Назначить событие</p>
            <label class="acd-field">
              <span class="acd-field__lab">Название</span>
              <input class="acd-input" value="Турнир рассветной печати" />
            </label>
            <label class="acd-field">
              <span class="acd-field__lab">Вид события</span>
              <select class="acd-select">
                <option>Дружеский турнир</option>
                <option>Тренировка новичков</option>
                <option>Разбор боя</option>
              </select>
            </label>
            <button type="button" class="acd-btn acd-btn--primary acd-btn--block" phx-click="schedule">
              {if @scheduled, do: "Событие внесено в расписание", else: "Опубликовать на доске"}
            </button>
          </section>

          <section class="acd-card">
            <p class="acd-card__title">Заявки на вступление</p>
            <div :for={name <- @approvals} class="acd-approve">
              <span>{name}</span>
              <span class="acd-approve__actions">
                <button class="acd-btn acd-btn--primary" type="button">Принять</button>
                <button class="acd-btn acd-btn--danger" type="button">Отказать</button>
              </span>
            </div>
          </section>

          <section class="acd-card">
            <p class="acd-card__title">Роли</p>
            <label class="acd-field">
              <span class="acd-field__lab">Капитан дуэлей</span>
              <select class="acd-select">
                <option>Мира Дол</option>
                <option>Альберт Северин</option>
                <option>Каэль Вейн</option>
              </select>
            </label>
            <label class="acd-field">
              <span class="acd-field__lab">Казначей</span>
              <select class="acd-select">
                <option>Селина Ров</option>
                <option>Овид Вар</option>
              </select>
            </label>
          </section>

          <section class="acd-card">
            <p class="acd-card__title">Знак и цвета</p>
            <p class="acd-card__meta">Цвета видны на клубной карточке и в будущих организациях.</p>
            <div class="acd-swatches">
              <button
                type="button"
                class={["acd-swatch", @accent == "gold" && "acd-swatch--on"]}
                style="background: linear-gradient(135deg, #5b211b, #a9791f);"
                phx-click="accent"
                phx-value-tone="gold"
                aria-label="Красное золото"
              >
              </button>
              <button
                type="button"
                class={["acd-swatch", @accent == "blue" && "acd-swatch--on"]}
                style="background: linear-gradient(135deg, #18384b, #7ecbff);"
                phx-click="accent"
                phx-value-tone="blue"
                aria-label="Синий огонь"
              >
              </button>
              <button
                type="button"
                class={["acd-swatch", @accent == "green" && "acd-swatch--on"]}
                style="background: linear-gradient(135deg, #2f3f2c, #7fae6b);"
                phx-click="accent"
                phx-value-tone="green"
                aria-label="Зелёная печать"
              >
              </button>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end
end
