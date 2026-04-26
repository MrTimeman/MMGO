defmodule MMGOWeb.GrimoireLive do
  use MMGOWeb, :live_view

  alias MMGO.Grimoires
  alias MMGO.Spells
  alias MMGOWeb.GameLiveHelpers

  @demo_grimoires [
    %{
      id: "demo-red",
      name: "Малый Красный",
      color: "#a02818",
      capacity: 8,
      spells: ["Удар Пламени", "Луч Огня", "Щит Пламени"]
    },
    %{
      id: "demo-chaos",
      name: "Гримуар Хаоса",
      color: "#6020a0",
      capacity: 12,
      spells: ["Захват Хаоса", "Рассеяние", "Удар Хаоса"]
    },
    %{id: "demo-battle", name: "Боевой", color: "#2a3a18", capacity: 5, spells: ["Стена Огня"]}
  ]

  def mount(_params, session, socket) do
    socket = GameLiveHelpers.assign_current_character(socket, session)
    character = socket.assigns.current_character
    grimoires = payload(Grimoires.list_grimoires_for_character(character.id))
    spells = Spells.list_spells_for_character(character.id)

    {:ok,
     assign(socket,
       page_title: "Гримуары",
       grimoires: if(grimoires == [], do: @demo_grimoires, else: grimoires),
       selected_id: (List.first(grimoires) || List.first(@demo_grimoires)).id,
       spells: spells
     )}
  end

  def handle_event("select_grimoire", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_id, id)}
  end

  def handle_event("remove_spell", %{"spell" => spell}, socket) do
    grimoires =
      Enum.map(socket.assigns.grimoires, fn grimoire ->
        if grimoire.id == socket.assigns.selected_id do
          %{grimoire | spells: Enum.reject(grimoire.spells, &(&1 == spell))}
        else
          grimoire
        end
      end)

    {:noreply, assign(socket, :grimoires, grimoires)}
  end

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :selected,
        Enum.find(assigns.grimoires, &(&1.id == assigns.selected_id)) ||
          List.first(assigns.grimoires)
      )

    ~H"""
    <Layouts.app flash={@flash} variant={:game}>
      <main id="grimoire-screen" class="zip-screen">
        <.zip_header
          title="Гримуары"
          subtitle={
            @selected && "#{@selected.name} · #{length(@selected.spells)}/#{@selected.capacity}"
          }
        />

        <section class="zip-content">
          <div id="grimoire-shelf-hook" class="grimoire-shelves">
            <div class="grimoire-books">
              <div
                :for={grimoire <- @grimoires}
                id={"grimoire-book-#{grimoire.id}"}
                class={["grimoire-book", grimoire.id == @selected.id && "is-selected"]}
                style={"--book-color: #{grimoire.color}"}
                phx-click="select_grimoire"
                phx-value-id={grimoire.id}
              >
                <span>{grimoire.name}</span>
                <small>{length(grimoire.spells)}/{grimoire.capacity}</small>
              </div>
            </div>
            <div class="grimoire-plank"></div>
          </div>

          <div :if={@selected} class="grimoire-detail">
            <.capacity_bar
              value={length(@selected.spells)}
              max={@selected.capacity}
              color={@selected.color}
            />

            <p class="zip-kicker">СОДЕРЖИМОЕ</p>
            <div class="zip-panel-list">
              <article
                :for={spell <- @selected.spells}
                class="grimoire-spell-card"
                style={"--school-color: #{@selected.color}"}
              >
                <div>
                  <h2>{spell}</h2>
                  <p>Инкантация сохранена в выбранном гримуаре</p>
                </div>
                <button type="button" phx-click="remove_spell" phx-value-spell={spell}>✕</button>
              </article>
            </div>

            <p class="zip-kicker">БИБЛИОТЕКА — нажмите чтобы добавить</p>
            <div class="zip-panel-list">
              <.link id="grimoire-spell-list-link" navigate={~p"/spells"} class="grimoire-library-row">
                Открыть список заклинаний <span>+</span>
              </.link>
            </div>
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

  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :color, :string, required: true

  defp capacity_bar(assigns) do
    assigns = assign(assigns, :pct, min(100, max(0, round(assigns.value / assigns.max * 100))))

    ~H"""
    <div class="zip-hp grimoire-capacity">
      <div><span>Заполненность</span><span>{@value}/{@max}</span></div>
      <div class="zip-hp__track">
        <span style={"width: #{@pct}%; background: #{@color}; box-shadow: 0 0 6px #{@color}99"}>
        </span>
      </div>
    </div>
    """
  end

  defp payload(grimoires) do
    Enum.map(grimoires, fn grimoire ->
      %{
        id: grimoire.id,
        name: grimoire.name,
        color: grimoire.metadata["color"] || "#6a4020",
        capacity: grimoire.capacity,
        spells: Enum.map(grimoire.entries, &((&1.spell && &1.spell.name) || "Безымянное"))
      }
    end)
  end
end
