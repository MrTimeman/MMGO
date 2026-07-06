defmodule MMGOWeb.SpellbookLive do
  use MMGOWeb, :live_view

  alias MMGO.Accounts
  alias MMGO.Spells
  alias MMGO.Spells.Compiler
  alias MMGOWeb.LocationGate

  @impl true
  def mount(_params, session, socket) do
    character = load_character(session)

    if is_nil(character) do
      {:ok, push_navigate(socket, to: ~p"/play/continue")}
    else
      case LocationGate.gate(socket, character, :tower) do
        {:halt, socket} ->
          {:ok, socket}

        {:ok, socket} ->
          spells = Spells.list_spells_for_character(character.id)

          {:ok,
           socket
           |> assign(:page_title, "Spellbook")
           |> assign(:character, character)
           |> assign(:spells, spells)
           |> assign(:compiling, false)
           |> assign(:last_spell, nil)
           |> assign(:compile_error, nil)}
      end
    end
  end

  @impl true
  def handle_event("hook_mounted", %{"hook" => "SpellCircle"}, socket) do
    socket =
      push_event(socket, "spell_circle_init", %{
        slots: default_slots(),
        current: %{}
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("spell_compile", params, socket) do
    character = socket.assigns.character

    if is_nil(character) do
      {:noreply, push_navigate(socket, to: ~p"/play/continue")}
    else
      formula = build_formula(params)
      school = params["school"] || ""

      attrs = %{
        "name" => params["name"] || formula,
        "formula" => formula,
        "school" => school,
        "base_spell_id" => params["base"]
      }

      case Compiler.compile_and_store(character, attrs) do
        {:ok, %{spell: spell}} ->
          spells = Spells.list_spells_for_character(character.id)

          {:noreply,
           socket
           |> assign(:compiling, false)
           |> assign(:last_spell, spell)
           |> assign(:compile_error, nil)
           |> assign(:spells, spells)}

        {:error, changeset} ->
          msg = changeset_error(changeset)

          {:noreply,
           socket
           |> assign(:compiling, false)
           |> assign(:compile_error, msg)}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-root" style="overflow-y: auto; padding: 2rem;">
      <%= if is_nil(@character) do %>
        <div style="text-align:center; margin-top: 20vh;">
          <h1 style="font-family: var(--font-serif); color: var(--color-accent); font-size: 2rem; margin-bottom: 1rem;">
            Spellbook
          </h1>
          <p style="color: var(--color-text-muted); margin-bottom: 2rem;">
            Continue local play to access your spellbook.
          </p>
          <a
            href={~p"/play/continue"}
            style="
            display: inline-block;
            padding: 0.75rem 2rem;
            background: var(--color-accent);
            color: #000;
            font-family: var(--font-serif);
            font-weight: bold;
            border-radius: 0.375rem;
            text-decoration: none;
          "
          >
            Enter the Tower
          </a>
        </div>
      <% else %>
        <div style="max-width: 900px; margin: 0 auto;">
          <a href={~p"/map"} class="map-back-link">← World map</a>
          <header style="margin-bottom: 2rem;">
            <h1 style="font-family: var(--font-serif); color: var(--color-accent); font-size: 1.75rem;">
              Spellbook — {@character.name}
            </h1>
            <p style="color: var(--color-text-muted); font-size: 0.875rem;">
              Level {@character.level} · Realm {@character.realm_id}
            </p>
            <div style="margin-top: 0.5rem;">
              <a
                href={~p"/pvp"}
                style="color: var(--color-text-muted); font-size: 0.875rem; text-decoration: underline;"
              >
                → Duel Arena
              </a>
            </div>
          </header>

          <section style="margin-bottom: 3rem;">
            <h2 style="font-family: var(--font-serif); color: var(--color-text); font-size: 1.25rem; margin-bottom: 1.5rem;">
              Forge a New Spell
            </h2>
            <p style="color: var(--color-text-muted); font-size: 0.8rem; margin-bottom: 1rem;">
              Fill each orbital slot with a word (Latin incantation words work best). When all required slots are filled, the circle charges — then compile.
            </p>
            <div
              id="spell-circle-root"
              phx-hook="SpellCircle"
              phx-update="ignore"
              style="min-height: 340px;"
            />

            <%= if @compiling do %>
              <p style="color: var(--color-text-muted); margin-top: 1rem; font-style: italic;">
                Compiling incantation…
              </p>
            <% end %>

            <%= if @compile_error do %>
              <div style="
                margin-top: 1rem;
                padding: 0.75rem 1rem;
                background: rgba(239,68,68,0.1);
                border: 1px solid var(--color-danger);
                border-radius: 0.375rem;
                color: var(--color-danger);
                font-size: 0.875rem;
              ">
                {@compile_error}
              </div>
            <% end %>

            <%= if @last_spell do %>
              <.spell_card spell={@last_spell} fresh={true} />
            <% end %>
          </section>

          <%= if @spells != [] do %>
            <section>
              <h2 style="font-family: var(--font-serif); color: var(--color-text); font-size: 1.25rem; margin-bottom: 1rem;">
                Known Spells ({length(@spells)})
              </h2>
              <div style="display: flex; flex-direction: column; gap: 0.75rem;">
                <%= for spell <- @spells do %>
                  <.spell_card spell={spell} fresh={false} />
                <% end %>
              </div>
            </section>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp spell_card(assigns) do
    ~H"""
    <div style={
      "background: var(--color-surface); border: 1px solid #{if @fresh, do: "var(--color-accent)", else: "var(--color-border)"}; border-radius: var(--panel-radius); padding: var(--panel-padding); transition: border-color 0.3s;"
    }>
      <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 0.5rem;">
        <h3 style={"font-family: var(--font-serif); color: #{if @fresh, do: "var(--color-accent)", else: "var(--color-text)"}; font-size: 1rem; margin: 0;"}>
          {@spell.name}
        </h3>
        <span style="
          font-size: 0.7rem;
          padding: 0.2rem 0.5rem;
          background: var(--color-surface-2);
          border-radius: 9999px;
          color: var(--color-text-muted);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        ">
          {@spell.school}
        </span>
      </div>
      <p style="font-size: 0.8rem; color: var(--color-text-muted); font-style: italic; margin-bottom: 0.5rem;">
        "{@spell.formula}"
      </p>
      <%= if @spell.description do %>
        <p style="font-size: 0.85rem; color: var(--color-text); margin-bottom: 0.5rem;">
          {@spell.description}
        </p>
      <% end %>
      <div style="display: flex; gap: 1rem; font-size: 0.75rem; color: var(--color-text-muted);">
        <span>Lvl {@spell.level_requirement}+</span>
        <span>Fatigue {@spell.fatigue_cost}</span>
        <span>Cooldown {@spell.cooldown_turns}t</span>
        <span>{@spell.delivery_form} · {@spell.targeting}</span>
        <%= if @spell.effects != [] do %>
          <span>{length(@spell.effects)} effect(s)</span>
        <% end %>
      </div>
    </div>
    """
  end

  defp load_character(%{"demo_character_id" => id}) when is_binary(id) do
    Accounts.get_character!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp load_character(_session), do: nil

  defp build_formula(params) do
    ["type", "element", "aspect", "effect", "time", "mana"]
    |> Enum.map(&Map.get(params, &1))
    |> Enum.reject(&(is_nil(&1) || &1 == ""))
    |> Enum.join(" ")
  end

  defp default_slots do
    [
      %{key: "school", label: "School", required: true},
      %{key: "type", label: "Action", required: true},
      %{key: "element", label: "Element", required: true},
      %{key: "aspect", label: "Aspect", required: true},
      %{key: "effect", label: "Effect", required: true},
      %{key: "time", label: "Duration", required: true},
      %{key: "mana", label: "Cost", required: true},
      %{key: "base", label: "Base Spell", required: false}
    ]
  end

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end
end
