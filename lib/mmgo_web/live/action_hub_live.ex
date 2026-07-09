defmodule MMGOWeb.ActionHubLive do
  @moduledoc """
  Design-pass screen — the core "you have arrived" hub (GDD §5.6).

  Every arrival at any location lands here: a scene image on top, an
  atmospheric block of text, and the list of things you can do at this
  physical place. There is no global navigation — the actions ARE the
  navigation, and they only exist because you are standing here.

  Three demo states are reviewable via the compass chips at the bottom:
  a city (Врата Зари), the Tower (Башня), and a wilderness road
  encounter. See docs/UI_DESIGN_BRIEF.md.
  """
  use MMGOWeb, :live_view

  import MMGOWeb.UIKit

  # Each demo location is a self-contained "sheet": the art label doubles
  # as the artist brief, the narrative is the Starsector-style event text,
  # and either `actions` (places to enter) or `choices` (an event) render.
  @locations %{
    city: %{
      name: "Врата Зари",
      kind: "город",
      art: "Врата Зари — рыночная площадь на закате",
      date: "14-е Месяца Жатвы, 847 год",
      narrative:
        "Солнце оседает за черепичные крыши, и Врата Зари загораются медью закатных огней. " <>
          "С рыночной площади тянет дымом жаровен и пряностями южных караванов, где-то бьёт " <>
          "вечерний колокол Академии. Здесь, за высокими стенами, не властны ни клинок, ни " <>
          "заклинание — лишь монета да доброе слово. Куда направишься, Альберт?",
      actions: [
        %{
          glyph: "⚖",
          title: "Лавка торговца",
          hint: "купить припасы и продать добычу",
          to: "/trade"
        },
        %{glyph: "❦", title: "Академия", hint: "лекции, экзамены и клубы", to: "/academy"},
        %{glyph: "⌂", title: "Ваша база", hint: "хранилище, мастерская, отдых", to: "/base"},
        %{
          glyph: "✦",
          title: "Снарядиться в путь",
          hint: "проложить дорогу к Башне",
          to: "/travel"
        }
      ]
    },
    tower: %{
      name: "Башня",
      kind: "башня",
      art: "Башня — чёрный шпиль над прибрежными утёсами",
      date: "14-е Месяца Жатвы, 847 год",
      narrative:
        "Башня вырастает из прибрежных утёсов, чёрная и безмолвная, и воздух вокруг неё дрожит " <>
          "от невидимой силы. Только здесь, вдали от городов, магия просыпается в полную мощь — " <>
          "здесь плетут заклинания, что в глуши обратились бы прахом. Снизу тянет холодом из " <>
          "распахнутого зева подземелья, откуда не всякий отряд возвращается. Гримуар в суме теплеет.",
      actions: [
        %{
          glyph: "✶",
          title: "Гримуар",
          hint: "плести и переплетать заклинания",
          to: "/spellbook"
        },
        %{
          glyph: "⚔",
          title: "Дуэльная площадка",
          hint: "вызвать соперника на поединок",
          to: "/pvp"
        },
        %{
          glyph: "◆",
          title: "Врата подземелья",
          hint: "собрать отряд перед спуском",
          to: "/party"
        }
      ]
    },
    wild: %{
      name: "Лесной тракт",
      kind: "глушь",
      art: "Волчья пустошь — встречный путник на тракте",
      date: "День 3 пути · Месяц Жатвы, 847 год",
      narrative:
        "Тракт вьётся сквозь Волчью пустошь, и придорожные вязы роняют жёлтый лист под копыта. " <>
          "Здесь нет ни стен, ни закона — только вы и дорога. Из-за поворота навстречу выходит " <>
          "путник в дорожном плаще; рука его лежит на поясе, а взгляд быстро считает ваши сумы. " <>
          "Он поднимает раскрытую ладонь — не то в приветствии, не то прикидывая, стоит ли " <>
          "ударить первым. Магия здесь мертва; всё решат сталь да смекалка.",
      choices: [
        %{
          key: "greet",
          glyph: "☙",
          title: "Поприветствовать",
          hint: "заговорить первым, показать пустые руки"
        },
        %{
          key: "trade",
          glyph: "⚖",
          title: "Предложить торговлю",
          hint: "раскрыть суму, сбить цену"
        },
        %{
          key: "attack",
          glyph: "⚔",
          title: "Напасть",
          hint: "ударить, пока он не решился",
          to: "/combat"
        },
        %{key: "avoid", glyph: "»", title: "Обойти стороной", hint: "сойти в подлесок, переждать"}
      ]
    }
  }

  @encounter_results %{
    "greet" =>
      "Путник медлит и опускает руку с пояса. «Дорога нынче недобрая, — бросает он. — Держись троп». " <>
        "Разойдясь миром, вы продолжаете путь.",
    "trade" =>
      "Незнакомец раскрывает суму: вяленое мясо, огниво, пара склянок мутного зелья. Торг недолог — " <>
        "в глуши цену не сбивают. Вы меняете десяток монет на припасы в дорогу.",
    "avoid" =>
      "Вы сходите с тракта в подлесок и пережидаете, пока чужак скроется за холмом. Осторожность " <>
        "стоила часа пути — зато шкура целее."
  }

  @impl true
  def mount(_params, _session, socket) do
    # TODO: wire — resolve the character's current location instead of the demo default.
    {:ok,
     socket
     |> assign(:page_title, "Локация")
     |> assign(:place, :city)
     |> assign(:encounter_result, nil)}
  end

  @impl true
  def handle_event("goto", %{"loc" => loc}, socket) do
    place = whitelist(loc)
    {:noreply, socket |> assign(:place, place) |> assign(:encounter_result, nil)}
  end

  @impl true
  def handle_event("choose", %{"key" => key}, socket) do
    # TODO: wire — real encounters branch into combat / trade / dialogue graphs.
    {:noreply, assign(socket, :encounter_result, Map.get(@encounter_results, key))}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :loc, @locations[assigns.place])

    ~H"""
    <div class="evh-scene">
      <div class="evh-shell">
        <div class="evh-hero">
          <.art_slot kind="hero" label={@loc.art} />
          <a href={~p"/map"} class="evh-exit">← На карту</a>
          <div class="evh-hero__veil"></div>
          <div class="evh-hero__caption">
            <span class={"evh-badge evh-badge--#{@place}"}>{@loc.kind}</span>
            <h1 class="evh-title">{@loc.name}</h1>
          </div>
        </div>

        <div class="evh-body">
          <p class="evh-date">{@loc.date}</p>
          <p class="evh-narrative">{@loc.narrative}</p>

          <%= if @loc[:actions] do %>
            <p class="evh-legend">Здесь можно</p>
            <div class="evh-actions">
              <.link :for={a <- @loc.actions} navigate={a.to} class="evh-action">
                <span class="evh-action__glyph">{a.glyph}</span>
                <span class="evh-action__text">
                  <span class="evh-action__title">{a.title}</span>
                  <span class="evh-action__hint">{a.hint}</span>
                </span>
                <span class="evh-action__chev">›</span>
              </.link>
            </div>
          <% end %>

          <%= if @loc[:choices] do %>
            <p class="evh-legend">Как поступишь</p>
            <div class="evh-actions">
              <%= for c <- @loc.choices do %>
                <%= if c[:to] do %>
                  <.link navigate={c.to} class="evh-action evh-action--peril">
                    <span class="evh-action__glyph">{c.glyph}</span>
                    <span class="evh-action__text">
                      <span class="evh-action__title">{c.title}</span>
                      <span class="evh-action__hint">{c.hint}</span>
                    </span>
                    <span class="evh-action__chev">›</span>
                  </.link>
                <% else %>
                  <button type="button" class="evh-action" phx-click="choose" phx-value-key={c.key}>
                    <span class="evh-action__glyph">{c.glyph}</span>
                    <span class="evh-action__text">
                      <span class="evh-action__title">{c.title}</span>
                      <span class="evh-action__hint">{c.hint}</span>
                    </span>
                  </button>
                <% end %>
              <% end %>
            </div>

            <%= if @encounter_result do %>
              <p class="evh-outcome">{@encounter_result}</p>
            <% end %>
          <% end %>
        </div>

        <div
          class="evh-compass"
          role="group"
          aria-label="Демонстрационные локации"
        >
          <span class="evh-compass__label">✧ обзор локаций ✧</span>
          <div class="evh-compass__chips">
            <button
              type="button"
              class={"evh-chip#{if @place == :city, do: " evh-chip--on"}"}
              phx-click="goto"
              phx-value-loc="city"
            >
              Врата Зари
            </button>
            <button
              type="button"
              class={"evh-chip#{if @place == :tower, do: " evh-chip--on"}"}
              phx-click="goto"
              phx-value-loc="tower"
            >
              Башня
            </button>
            <button
              type="button"
              class={"evh-chip#{if @place == :wild, do: " evh-chip--on"}"}
              phx-click="goto"
              phx-value-loc="wild"
            >
              Тракт
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp whitelist("tower"), do: :tower
  defp whitelist("wild"), do: :wild
  defp whitelist(_), do: :city
end
