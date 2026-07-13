defmodule MMGOWeb.LocationGate do
  @moduledoc """
  Map-first location gating for LiveViews.

  GDD §5: the world map (`/map`) is the interface. Certain activities (magic,
  duels, academy business, organization business) can only happen once a
  character has physically travelled to a location of the right kind. This
  module is the single place that enforces that rule.

  Usage from a LiveView's `mount/3`, *after* the shared `GameAuth` boundary has
  loaded and confirmed the current scope. This gate only concerns itself with
  *where* that authenticated character currently is:

      case LocationGate.gate(socket, character, :tower) do
        {:ok, socket} -> {:ok, assign(socket, :character, character)}
        {:halt, socket} -> {:ok, socket}
      end
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias MMGO.Repo
  alias MMGO.Worlds.Location

  @type required_kind :: :tower | :city

  @flash_messages %{
    tower: "Magic only works at the Tower. Travel there on the map.",
    city: "You need to be in a city for that."
  }

  @doc """
  Checks whether `character` currently satisfies the `required` location kind.

  Returns `{:ok, socket}` when the gate passes, or `{:halt, socket}` with the
  socket already redirected to `/map` and flashed with an in-world message
  when it does not (including when `character` is `nil` or has no current
  location).
  """
  @spec gate(Phoenix.LiveView.Socket.t(), MMGO.Accounts.Character.t() | nil, required_kind()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def gate(socket, character, required)

  def gate(socket, nil, _required), do: {:halt, redirect_to_map(socket, :city)}

  def gate(socket, %{} = character, required) when required in [:tower, :city] do
    character = ensure_location_loaded(character)

    if satisfies?(character, required) do
      {:ok, socket}
    else
      {:halt, redirect_to_map(socket, required)}
    end
  end

  defp satisfies?(%{current_location: %Location{kind: kind}}, required), do: kind == required
  defp satisfies?(_character, _required), do: false

  defp ensure_location_loaded(%{current_location: %Location{}} = character), do: character

  defp ensure_location_loaded(character), do: Repo.preload(character, :current_location)

  defp redirect_to_map(socket, required) do
    socket
    |> put_flash(:error, Map.fetch!(@flash_messages, required))
    |> push_navigate(to: "/map")
  end

  @doc """
  Helper for rendering the "return to the map" link at the top of every
  gated view. Not itself part of the gating logic — the map is always
  reachable, it's the hub.
  """
  def assign_map_back_link(socket), do: assign(socket, :show_map_back_link, true)
end
