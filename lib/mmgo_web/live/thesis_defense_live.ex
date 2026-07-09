defmodule MMGOWeb.ThesisDefenseLive do
  @moduledoc """
  Design-pass thesis defense ceremony (GDD §9.10).

  Demo-only: no backend wiring. The `:id` param is accepted for the routed
  ceremony URL but the content is a scripted demonstration.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  @panel [
    %{name: "проф. Веладрис", role: "наставник", art: "Профессор Веладрис — огненная кафедра"},
    %{
      name: "проф. Ил-Сарра",
      role: "оппонент",
      art: "Профессор Ил-Сарра — кафедра хаоса",
      rival?: true
    },
    %{name: "магистр Мовен", role: "секретарь", art: "Магистр Мовен — латинская грамматика"}
  ]

  @rounds [
    %{
      who: "проф. Веладрис",
      question: "Докажите, что ваша печать сохраняет форму после третьего повторения Actio.",
      answers: [
        "Сослаться на огненную матрицу и показать, где уходит избыточный жар.",
        "Объявить, что форма держится силой воли.",
        "Попросить перенести вопрос в письменные правки."
      ],
      reaction: "Наставник кивает: жар отведён в край печати, аргумент принят."
    },
    %{
      who: "проф. Ил-Сарра",
      question: "Хаос в вашей работе декоративен или даёт измеримый прирост?",
      answers: [
        "Показать сравнение трёх компиляций и признать предел метода.",
        "Ответить, что Хаос не обязан измеряться.",
        "Уклониться к истории школы Огня."
      ],
      reaction: "Оппонент отмечает слабое место, но признаёт честность измерения."
    },
    %{
      who: "магистр Мовен",
      question: "Почему латинская связка Forma Ignis не ломает вторую школу?",
      answers: [
        "Развести школу и форму: Ignis задаёт оболочку, Chaos — возмущение.",
        "Сослаться на традицию кафедры.",
        "Промолчать."
      ],
      reaction: "Секретарь заносит формулировку в протокол без замечаний."
    }
  ]

  @impl true
  def mount(params, _session, socket) do
    # TODO: wire — load thesis, candidate, advisor, defense state and panel by id.
    {:ok,
     socket
     |> assign(:page_title, "Защита тезиса")
     |> assign(:defense_id, params["id"])
     |> assign(:panel, @panel)
     |> assign(:rounds, @rounds)
     |> assign(:chosen_rounds, %{})
     |> assign(:verdict, nil)}
  end

  @impl true
  def handle_event("answer", %{"round" => round, "answer" => answer}, socket) do
    {:noreply, update(socket, :chosen_rounds, &Map.put(&1, String.to_integer(round), answer))}
  end

  @impl true
  def handle_event("verdict", %{"kind" => kind}, socket) do
    {:noreply, assign(socket, :verdict, verdict(kind))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="acd-screen">
      <div class="acd-shell">
        <a href={~p"/academy"} class="acd-exit">← В Академию</a>

        <div class="acd-hero">
          <.art_slot
            kind="banner"
            label="Академия наук — открытая защита тезиса в малой аудитории"
          />
          <div class="acd-hero__veil"></div>
          <div class="acd-hero__cap">
            <p class="acd-eyebrow">Открытая защита · §9.10</p>
            <h1 class="acd-hero__title">Тезис принят к слушанию</h1>
            <p class="acd-hero__sub">аудитория открыта для студентов и профессоров города</p>
          </div>
        </div>

        <div class="acd-body">
          <section class="acd-card">
            <p class="acd-card__title">Кандидат: Альберт Северин</p>
            <p class="acd-card__meta">
              Тезис: «Двойная печать огня и хаоса для управляемого всплеска».
              Наставник: проф. Веладрис. Номер дела: {@defense_id || "demo"}.
            </p>
          </section>

          <section class="acd-section">
            <div class="acd-section__head">
              <h2 class="acd-section__title">Комиссия</h2>
              <span class="acd-section__aside">три голоса</span>
            </div>
            <div class="acd-defense__panel">
              <div
                :for={prof <- @panel}
                class={["acd-prof", Map.get(prof, :rival?) && "acd-prof--rival"]}
              >
                <div class="acd-prof__portrait">
                  <.art_slot kind="portrait" label={prof.art} />
                </div>
                <span class="acd-prof__name">{prof.name}</span>
                <span class="acd-prof__role">{prof.role}</span>
                <span :if={Map.get(prof, :rival?)} class="acd-badge acd-badge--rival">соперник</span>
              </div>
            </div>
          </section>

          <p class="acd-audience">
            В задних рядах шепчутся студенты: защита открыта, и каждый вопрос станет слухом.
          </p>

          <section class="acd-dialogue">
            <div :for={{round, idx} <- Enum.with_index(@rounds)} class="acd-q">
              <div class="acd-q__who">Раунд {idx + 1} · {round.who}</div>
              <div class="acd-q__txt">«{round.question}»</div>
              <div class="acd-answers">
                <button
                  :for={{answer, answer_idx} <- Enum.with_index(round.answers)}
                  type="button"
                  class={[
                    "acd-answer",
                    Map.get(@chosen_rounds, idx) == Integer.to_string(answer_idx) &&
                      "acd-answer--chosen"
                  ]}
                  phx-click="answer"
                  phx-value-round={idx}
                  phx-value-answer={answer_idx}
                >
                  {answer}
                </button>
              </div>
              <div :if={Map.has_key?(@chosen_rounds, idx)} class="acd-reaction">
                {round.reaction}
              </div>
            </div>
          </section>

          <%= if @verdict do %>
            <section class={"acd-card acd-verdict acd-verdict--#{@verdict.kind}"}>
              <div class="acd-seal">✦</div>
              <p class="acd-verdict__t">{@verdict.title}</p>
              <p class="acd-verdict__d">{@verdict.note}</p>
            </section>
          <% else %>
            <section class="acd-card">
              <p class="acd-card__title">Голосование комиссии</p>
              <p class="acd-card__meta">
                После ответов председатель гасит свечу, секретарь закрывает протокол, и печать
                Академии ложится на решение.
              </p>
              <div class="acd-answers">
                <button
                  class="acd-btn acd-btn--primary acd-btn--block"
                  type="button"
                  phx-click="verdict"
                  phx-value-kind="accept"
                >
                  Открыть вердикт: принято
                </button>
                <button
                  class="acd-btn acd-btn--block"
                  type="button"
                  phx-click="verdict"
                  phx-value-kind="revise"
                >
                  Принято с правками
                </button>
                <button
                  class="acd-btn acd-btn--danger acd-btn--block"
                  type="button"
                  phx-click="verdict"
                  phx-value-kind="reject"
                >
                  Отклонено
                </button>
              </div>
            </section>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp verdict("revise") do
    %{
      kind: "revise",
      title: "Принято с правками",
      note:
        "Кандидат получает один игровой сезон на уточнение латинской связки, профессорский путь остаётся открыт."
    }
  end

  defp verdict("reject") do
    %{
      kind: "reject",
      title: "Отклонено",
      note:
        "Тезис уходит на переработку на один игровой сезон. Второй отказ подряд закроет путь к профессорству."
    }
  end

  defp verdict(_) do
    %{
      kind: "accept",
      title: "Принято",
      note:
        "Академия признаёт вклад кандидата. Следующий шаг — кафедра, первый курс и собственные ученики."
    }
  end
end
