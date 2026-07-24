defmodule MMGOWeb.UIKit do
  @moduledoc """
  Shared UI pieces for game screens.

  Import in a LiveView with `import MMGOWeb.UIKit`.
  """
  use Phoenix.Component

  @art_sizes %{
    "hero" => {750, 500},
    "banner" => {750, 320},
    "scene" => {600, 600},
    "portrait" => {300, 400},
    "icon" => {128, 128}
  }

  @doc """
  Renders a quiet, decorative scene marker at the requested aspect ratio.

      <.art_slot kind="hero" label="Городские ворота" id="art-city-gate" />
      <.art_slot w={750} h={500} label="Таверна" variant="parchment" />

  * `kind` — one of hero (750×500, 3:2 full-width header), banner (750×320),
    scene (600×600), portrait (300×400), icon (128×128), or explicit `w`/`h`.
  * `variant` — "dark" (default, for world screens) or "parchment"
    (for document screens).

  The marker is deliberately presentation-only. It never exposes production
  notes, export dimensions, or promises of artwork to players.
  """
  attr :id, :string, default: nil
  attr :kind, :string, default: nil
  attr :w, :integer, default: nil
  attr :h, :integer, default: nil
  attr :label, :string, required: true
  attr :variant, :string, default: "dark"
  attr :class, :string, default: nil

  def art_slot(assigns) do
    {w, h} =
      cond do
        assigns.w && assigns.h -> {assigns.w, assigns.h}
        assigns.kind -> Map.fetch!(@art_sizes, assigns.kind)
        true -> {750, 500}
      end

    symbol =
      case assigns.kind do
        "icon" -> label_initial(assigns.label)
        _kind -> "✦"
      end

    assigns = assign(assigns, w: w, h: h, symbol: symbol)

    ~H"""
    <figure
      id={@id}
      class={["art-slot", "art-slot--#{@variant}", @kind && "art-slot--#{@kind}", @class]}
      style={"--art-ratio: #{@w} / #{@h};"}
      aria-hidden="true"
    >
      <div class="art-slot__frame">
        <span class="art-slot__corner art-slot__corner--tl"></span>
        <span class="art-slot__corner art-slot__corner--tr"></span>
        <span class="art-slot__corner art-slot__corner--bl"></span>
        <span class="art-slot__corner art-slot__corner--br"></span>
        <div class="art-slot__inner">
          <span class="art-slot__orbit"></span>
          <span class="art-slot__sigil">{@symbol}</span>
        </div>
      </div>
    </figure>
    """
  end

  defp label_initial(label) when is_binary(label) do
    label
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "◆"
      initial -> String.upcase(initial)
    end
  end

  defp label_initial(_label), do: "◆"
end
