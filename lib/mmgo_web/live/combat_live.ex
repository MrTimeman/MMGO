defmodule MMGOWeb.CombatLive do
  use MMGOWeb, :live_view

  alias MMGO.Combat
  alias MMGOWeb.GameLiveHelpers

  @enemy_max_hp 110
  @party_max_hp 90

  @spells [
    %{
      id: "chaos-grip",
      name: "Захват Хаоса",
      school: "Хаос",
      color: "#9030b0",
      damage: 18,
      state: {"Захвачен", "#9030b0"}
    },
    %{
      id: "dissipate",
      name: "Рассеяние",
      school: "Хаос",
      color: "#9030b0",
      damage: 14,
      state: nil
    },
    %{
      id: "fire-strike",
      name: "Удар Пламени",
      school: "Огонь",
      color: "#e05030",
      damage: 22,
      state: {"Горит", "#e05030"}
    },
    %{
      id: "fire-wall",
      name: "Стена Огня",
      school: "Огонь",
      color: "#e05030",
      damage: 12,
      state: {"Открыт", "#e08040"}
    }
  ]

  @impl true
  def mount(%{"id" => "demo"}, session, socket) do
    socket = GameLiveHelpers.assign_current_character(socket, session)

    {:ok,
     socket
     |> assign_base(socket.assigns.current_character.name, nil)
     |> assign(:cast_form, to_form(%{"incantation" => ""}, as: :cast))}
  end

  def mount(%{"id" => id}, session, socket) do
    socket = GameLiveHelpers.assign_current_character(socket, session)
    combat = Combat.get_combat!(id)

    enemy =
      Enum.find(combat.participants, &(&1.character_id != socket.assigns.current_character.id))

    {:ok,
     socket
     |> assign_base(
       socket.assigns.current_character.name,
       combat,
       (enemy && enemy.display_name) || "Противник"
     )
     |> assign(:cast_form, to_form(%{"incantation" => ""}, as: :cast))}
  end

  @impl true
  def handle_event("select_spell", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_spell_id, id)}
  end

  def handle_event("cast", %{"cast" => %{"incantation" => incantation}}, socket) do
    incantation = incantation |> to_string() |> String.trim()

    if incantation == "" or socket.assigns.phase == :victory or socket.assigns.phase == :defeat do
      {:noreply, assign(socket, :cast_form, to_form(%{"incantation" => incantation}, as: :cast))}
    else
      spell =
        Enum.find(@spells, &(&1.id == socket.assigns.selected_spell_id)) || List.first(@spells)

      enemy_hp = max(socket.assigns.enemy_hp - spell.damage, 0)
      states = add_state(socket.assigns.states, spell.state)

      player_line =
        "⚡ «#{incantation}». #{spell.name} срывается с круга и наносит #{spell.damage} урона."

      {phase, party_hp, extra_log} =
        if enemy_hp <= 0 do
          {:victory, socket.assigns.party_hp, ["✦ Враг повержен. Победа."]}
        else
          counter = 6 + rem(socket.assigns.turn * 5 + spell.damage, 11)
          party_hp = max(socket.assigns.party_hp - counter, 0)

          if party_hp <= 0 do
            {:defeat, party_hp,
             [
               "#{socket.assigns.enemy_name} отвечает тёмным импульсом. Отряд теряет #{counter} HP.",
               "Отряд разбит. Вернитесь позже."
             ]}
          else
            {:input, party_hp,
             [
               "#{socket.assigns.enemy_name} отвечает тёмным импульсом. Отряд теряет #{counter} HP.",
               "Ход #{socket.assigns.turn + 1}."
             ]}
          end
        end

      {:noreply,
       socket
       |> assign(:enemy_hp, enemy_hp)
       |> assign(:party_hp, party_hp)
       |> assign(:states, states)
       |> assign(:phase, phase)
       |> assign(:turn, socket.assigns.turn + 1)
       |> assign(:log, socket.assigns.log ++ [player_line] ++ extra_log)
       |> assign(:cast_form, to_form(%{"incantation" => ""}, as: :cast))}
    end
  end

  def handle_event("restart", _params, socket) do
    {:noreply,
     socket
     |> assign_base(
       socket.assigns.participant_name,
       socket.assigns.combat,
       socket.assigns.enemy_name
     )
     |> assign(:cast_form, to_form(%{"incantation" => ""}, as: :cast))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} variant={:game}>
      <main id="combat-screen" class="zip-screen">
        <.zip_header title={"Бой · Ход #{@turn}"} subtitle="Подземелье, Уровень 2" />

        <section class="combat-layout">
          <div class="combat-enemy">
            <div class="combat-enemy__head">
              <div>
                <h2>{@enemy_name}</h2>
                <p>Ур. 14 · Смерть</p>
              </div>
              <div class="combat-states">
                <span :for={{label, color} <- @states} style={"--state-color: #{color}"}>
                  {label}
                </span>
              </div>
            </div>
            <.hp_bar
              id="combat-enemy-hp"
              label="HP противника"
              value={@enemy_hp}
              max={@enemy_max_hp}
              color="#604080"
            />
          </div>

          <div id="combat-log" class="combat-log">
            <p :for={{entry, index} <- Enum.with_index(@log)} class={log_class(entry, index)}>
              {entry}
            </p>
          </div>

          <div class="combat-party">
            <.hp_bar
              id="combat-party-hp"
              label="HP отряда"
              value={@party_hp}
              max={@party_max_hp}
              color="#60a060"
            />
          </div>

          <div class="combat-actions">
            <div class="combat-spell-strip">
              <button
                :for={spell <- @spells}
                type="button"
                class={[@selected_spell_id == spell.id && "is-selected"]}
                style={"--school-color: #{spell.color}"}
                phx-click="select_spell"
                phx-value-id={spell.id}
              >
                {spell.name}
              </button>
            </div>

            <%= if @phase in [:victory, :defeat] do %>
              <button id="combat-restart" type="button" class="zip-gold-button" phx-click="restart">
                Новый бой
              </button>
              <.link navigate={~p"/play"} class="zip-sub-link">Вернуться к карте</.link>
            <% else %>
              <.form for={@cast_form} id="combat-cast-form" phx-submit="cast" class="combat-cast-row">
                <.input
                  field={@cast_form[:incantation]}
                  type="text"
                  id="combat-incantation-input"
                  class="combat-incantation-input"
                  placeholder="Ictus ignis magnus..."
                />
                <button id="combat-action-spell" type="submit">Бросить</button>
              </.form>
            <% end %>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  defp zip_header(assigns) do
    ~H"""
    <header class="zip-telegram-header">
      <div>
        <h1>{@title}</h1>
        <p :if={@subtitle}>{@subtitle}</p>
      </div>
    </header>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :color, :string, required: true

  defp hp_bar(assigns) do
    assigns = assign(assigns, :pct, min(100, max(0, round(assigns.value / assigns.max * 100))))

    ~H"""
    <div id={@id} class="zip-hp">
      <div><span>{@label}</span><span>{@value}/{@max}</span></div>
      <div class="zip-hp__track">
        <span style={"width: #{@pct}%; background: #{@color}; box-shadow: 0 0 6px #{@color}99"}>
        </span>
      </div>
    </div>
    """
  end

  defp assign_base(socket, participant_name, combat, enemy_name \\ "Теневой Стражник") do
    assign(socket,
      page_title: "Бой",
      combat: combat,
      participant_name: participant_name,
      enemy_name: enemy_name,
      enemy_hp: @enemy_max_hp,
      enemy_max_hp: @enemy_max_hp,
      party_hp: 74,
      party_max_hp: @party_max_hp,
      turn: 1,
      phase: :input,
      states: [{"Щит", "#5f8a4a"}, {"Усилен", "#c8a44a"}],
      spells: @spells,
      selected_spell_id: "chaos-grip",
      log: [
        "Теневой Стражник материализовался из темноты. Его форма нестабильна — края размыты, словно он не до конца существует в этом мире.",
        "Ход 1. Выберите базовое заклинание и произнесите инкантацию."
      ]
    )
  end

  defp add_state(states, nil), do: states

  defp add_state(states, {label, _color} = state) do
    if Enum.any?(states, fn {existing, _color} -> existing == label end),
      do: states,
      else: states ++ [state]
  end

  defp log_class(_entry, 0), do: "is-narrative"
  defp log_class("Ход" <> _rest, _index), do: "is-system"
  defp log_class("✦" <> _rest, _index), do: "is-system"
  defp log_class("Отряд разбит" <> _rest, _index), do: "is-enemy"
  defp log_class("⚡" <> _rest, _index), do: "is-player"

  defp log_class(entry, _index) when is_binary(entry) do
    if String.contains?(entry, "отвечает"), do: "is-enemy", else: "is-system"
  end
end
