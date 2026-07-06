defmodule MMGOWeb.DuelLive do
  use MMGOWeb, :live_view

  alias MMGO.Accounts
  alias MMGO.Combat
  alias MMGO.Combat.Resolution, as: CombatResolution
  alias MMGO.PVP
  alias MMGOWeb.LocationGate

  @impl true
  def mount(_params, session, socket) do
    character = load_character(session, :demo_character_id)

    if is_nil(character) do
      {:ok, push_navigate(socket, to: ~p"/play/continue")}
    else
      case LocationGate.gate(socket, character, :tower) do
        {:halt, socket} ->
          {:ok, socket}

        {:ok, socket} ->
          opponent = load_character(session, :demo_opponent_id)

          duel = PVP.active_duel_for_character(character.id)
          pending_duels = PVP.pending_duels_for_character(character.id)

          {:ok,
           socket
           |> assign(:page_title, "Duel Arena")
           |> assign(:character, character)
           |> assign(:opponent, opponent)
           |> assign(:duel, duel && PVP.get_duel!(duel.id))
           |> assign(:pending_duels, pending_duels)
           |> assign(:viewing_as, :challenger)
           |> assign(:error, nil)}
      end
    end
  end

  @impl true
  def handle_event("hook_mounted", %{"hook" => "DuelChallenge"}, socket) do
    socket = push_duel_update(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("challenge_bot", _params, socket) do
    %{character: challenger, opponent: opponent} = socket.assigns

    cond do
      is_nil(challenger) ->
        {:noreply, push_navigate(socket, to: ~p"/play/continue")}

      is_nil(opponent) ->
        {:noreply,
         assign(socket, :error, "Local opponent not set up. Visit /play/continue first.")}

      true ->
        case PVP.challenge_duel(challenger, opponent, 100) do
          {:ok, duel} ->
            duel = PVP.get_duel!(duel.id)
            pending = PVP.pending_duels_for_character(challenger.id)

            {:noreply,
             socket
             |> assign(:duel, duel)
             |> assign(:pending_duels, pending)
             |> assign(:error, nil)
             |> push_duel_update()}

          {:error, changeset} ->
            msg = changeset_error(changeset)
            {:noreply, assign(socket, :error, msg)}
        end
    end
  end

  @impl true
  def handle_event("duel_accept", %{"duel_id" => duel_id}, socket) do
    duel = PVP.get_duel!(duel_id)
    actor = viewer_character(socket)

    case PVP.accept_duel(duel, actor) do
      {:ok, updated_duel} ->
        {:noreply,
         socket
         |> assign(:duel, updated_duel)
         |> push_duel_update()}

      {:error, changeset} ->
        msg = changeset_error(changeset)
        {:noreply, assign(socket, :error, msg)}
    end
  end

  @impl true
  def handle_event("duel_reject", %{"duel_id" => duel_id}, socket) do
    duel = PVP.get_duel!(duel_id)
    actor = viewer_character(socket)

    case PVP.reject_duel(duel, actor) do
      {:ok, updated_duel} ->
        updated_duel = PVP.get_duel!(updated_duel.id)

        {:noreply,
         socket
         |> assign(:duel, updated_duel)
         |> push_duel_update()}

      {:error, changeset} ->
        msg = changeset_error(changeset)
        {:noreply, assign(socket, :error, msg)}
    end
  end

  @impl true
  def handle_event("duel_cancel", %{"duel_id" => duel_id}, socket) do
    duel = PVP.get_duel!(duel_id)
    actor = viewer_character(socket)

    case PVP.cancel_duel(duel, actor) do
      {:ok, updated_duel} ->
        updated_duel = PVP.get_duel!(updated_duel.id)

        {:noreply,
         socket
         |> assign(:duel, updated_duel)
         |> push_duel_update()}

      {:error, changeset} ->
        msg = changeset_error(changeset)
        {:noreply, assign(socket, :error, msg)}
    end
  end

  @impl true
  def handle_event("duel_resolve_combat", %{"duel_id" => duel_id}, socket) do
    duel = PVP.get_duel!(duel_id)

    with %{combat: %{} = combat} <- duel,
         true <- combat.status in [:locked, :active_turn],
         {:ok, resolved_combat} <- Combat.resolve_turn(combat),
         {:ok, _result} <- CombatResolution.finalize(resolved_combat) do
      updated_duel = PVP.get_duel!(duel_id)

      {:noreply,
       socket
       |> assign(:duel, updated_duel)
       |> assign(:error, nil)
       |> push_duel_update()}
    else
      %{combat: nil} ->
        {:noreply, assign(socket, :error, "This duel has no combat to resolve.")}

      false ->
        {:noreply, assign(socket, :error, "Combat is not ready to resolve yet.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :error, changeset_error(changeset))}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Could not resolve combat: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("switch_view", _params, socket) do
    new_view =
      if socket.assigns.viewing_as == :challenger, do: :opponent, else: :challenger

    {:noreply, assign(socket, :viewing_as, new_view)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-root" style="overflow-y: auto; padding: 2rem;">
      <%= if is_nil(@character) do %>
        <div style="text-align:center; margin-top: 20vh;">
          <h1 style="font-family: var(--font-serif); color: var(--color-accent); font-size: 2rem; margin-bottom: 1rem;">
            Duel Arena
          </h1>
          <p style="color: var(--color-text-muted); margin-bottom: 2rem;">
            Continue local play to access the arena.
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
        <div style="max-width: 700px; margin: 0 auto;">
          <a href={~p"/map"} class="map-back-link">← World map</a>
          <header style="margin-bottom: 2rem;">
            <h1 style="font-family: var(--font-serif); color: var(--color-accent); font-size: 1.75rem;">
              Duel Arena
            </h1>
            <div style="display: flex; gap: 1.5rem; font-size: 0.875rem; color: var(--color-text-muted); margin-top: 0.5rem;">
              <span>
                Viewing as:
                <strong style="color: var(--color-text);">
                  {if @viewing_as == :challenger,
                    do: @character.name,
                    else: @opponent && @opponent.name}
                </strong>
              </span>
              <%= if @opponent do %>
                <button
                  phx-click="switch_view"
                  style="color: var(--color-text-muted); text-decoration: underline; background: none; border: none; cursor: pointer; font-size: inherit; padding: 0;"
                >
                  Switch to {if @viewing_as == :challenger, do: @opponent.name, else: @character.name}
                </button>
              <% end %>
              <a
                href={~p"/spellbook"}
                style="color: var(--color-text-muted); text-decoration: underline;"
              >
                ← Spellbook
              </a>
            </div>
          </header>

          <%= if @error do %>
            <div style="
              margin-bottom: 1rem;
              padding: 0.75rem 1rem;
              background: rgba(239,68,68,0.1);
              border: 1px solid var(--color-danger);
              border-radius: 0.375rem;
              color: var(--color-danger);
              font-size: 0.875rem;
            ">
              {@error}
            </div>
          <% end %>

          <%= if is_nil(@duel) && @pending_duels == [] do %>
            <div style="
              background: var(--color-surface);
              border: 1px solid var(--color-border);
              border-radius: var(--panel-radius);
              padding: 2rem;
              text-align: center;
              margin-bottom: 2rem;
            ">
              <p style="color: var(--color-text-muted); margin-bottom: 1.5rem;">
                No active duels. Challenge the bot to a wager — loser pays winner 200 gold (100 stake each, 5% tax).
              </p>
              <%= if @opponent do %>
                <button
                  phx-click="challenge_bot"
                  style="
                    padding: 0.6rem 1.5rem;
                    background: var(--color-accent);
                    color: #000;
                    font-family: var(--font-serif);
                    font-weight: bold;
                    border: none;
                    border-radius: 0.375rem;
                    cursor: pointer;
                    font-size: 0.9rem;
                  "
                >
                  Challenge {@opponent.name}
                </button>
              <% else %>
                <a
                  href={~p"/play/continue"}
                  style="color: var(--color-text-muted); text-decoration: underline; font-size: 0.875rem;"
                >
                  Set up local opponent via /play/continue
                </a>
              <% end %>
            </div>
          <% end %>

          <%= if @duel do %>
            <div
              id="duel-hook-root"
              phx-hook="DuelChallenge"
              phx-update="ignore"
              style="margin-bottom: 2rem;"
            />

            <div style="
              background: var(--color-surface);
              border: 1px solid var(--color-border);
              border-radius: var(--panel-radius);
              padding: 1rem;
              font-size: 0.8rem;
              color: var(--color-text-muted);
            ">
              <strong style="color: var(--color-text);">Combat Notes</strong>
              <br /> Status: <strong>{@duel.status}</strong>
              · Stake: <strong>{@duel.stake_amount} gold each</strong>
              · Pot: <strong>{@duel.pot_amount} gold</strong>
              <%= if @duel.winner_character do %>
                · Winner:
                <strong style="color: var(--color-safe);">{@duel.winner_character.name}</strong>
              <% end %>
            </div>

            <%= if @duel.status == :active do %>
              <div style="margin-top: 1rem;">
                <button
                  phx-click="duel_resolve_combat"
                  phx-value-duel_id={@duel.id}
                  style="
                    padding: 0.6rem 1.5rem;
                    background: var(--color-accent);
                    color: #000;
                    font-family: var(--font-serif);
                    font-weight: bold;
                    border: none;
                    border-radius: 0.375rem;
                    cursor: pointer;
                    font-size: 0.9rem;
                  "
                >
                  Resolve Combat Turn
                </button>
              </div>
            <% end %>
          <% end %>

          <%= for pending <- @pending_duels do %>
            <%= if is_nil(@duel) || pending.id != @duel.id do %>
              <div style="
                background: var(--color-surface);
                border: 1px solid var(--color-border);
                border-radius: var(--panel-radius);
                padding: 1rem;
                margin-bottom: 0.5rem;
                font-size: 0.875rem;
              ">
                Pending duel #{String.slice(pending.id, 0, 8)} · stake: {pending.stake_amount}
              </div>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp push_duel_update(%{assigns: %{duel: nil}} = socket), do: socket

  defp push_duel_update(%{assigns: %{duel: duel, viewing_as: viewing_as}} = socket) do
    challenger = duel.challenger_character
    opponent = duel.opponent_character
    winner = duel.winner_character

    viewer_role =
      cond do
        viewing_as == :challenger -> "challenger"
        true -> "opponent"
      end

    push_event(socket, "duel_update", %{
      duel_id: duel.id,
      status: to_string(duel.status),
      challenger: format_char(challenger),
      opponent: format_char(opponent),
      stake: duel.stake_amount,
      pot: duel.pot_amount,
      winner_name: winner && winner.name,
      viewer_role: viewer_role
    })
  end

  defp format_char(nil), do: nil

  defp format_char(char) do
    %{name: char.name, gender: nil, avatar_url: nil}
  end

  defp viewer_character(%{assigns: %{viewing_as: :opponent, opponent: opponent}}), do: opponent
  defp viewer_character(%{assigns: %{character: character}}), do: character

  defp load_character(session, key) do
    case session[to_string(key)] do
      nil ->
        nil

      id ->
        Accounts.get_character!(id)
    end
  rescue
    Ecto.NoResultsError -> nil
  end

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end
end
