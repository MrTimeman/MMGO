defmodule MMGOWeb.UIKit do
  @moduledoc """
  Shared UI pieces for the design-pass screens (see docs/UI_DESIGN_BRIEF.md).

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
  Placeholder frame for artwork that will be drawn by human artists.

  Renders an ornate frame at the correct aspect ratio with the export
  dimensions printed inside (dimensions are @2x export pixels; the frame
  itself displays at half size in CSS px).

      <.art_slot kind="hero" label="Городские ворота" id="art-city-gate" />
      <.art_slot w={750} h={500} label="Таверна" variant="parchment" />

  * `kind` — one of hero (750×500, 3:2 full-width header), banner (750×320),
    scene (600×600), portrait (300×400), icon (128×128). Or pass explicit
    `w`/`h` instead.
  * `variant` — "dark" (default, for world screens) or "parchment"
    (for document screens).
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

    assigns = assign(assigns, w: w, h: h)

    ~H"""
    <figure
      id={@id}
      class={["art-slot", "art-slot--#{@variant}", @kind && "art-slot--#{@kind}", @class]}
      style={"--art-ratio: #{@w} / #{@h};"}
      data-art-label={@label}
      data-art-size={"#{@w}x#{@h}"}
    >
      <div class="art-slot__frame">
        <span class="art-slot__corner art-slot__corner--tl"></span>
        <span class="art-slot__corner art-slot__corner--tr"></span>
        <span class="art-slot__corner art-slot__corner--bl"></span>
        <span class="art-slot__corner art-slot__corner--br"></span>
        <div class="art-slot__inner">
          <span class="art-slot__sigil">✦</span>
          <span class="art-slot__label">{@label}</span>
          <span class="art-slot__dims">{@w}×{@h}</span>
        </div>
      </div>
    </figure>
    """
  end
end
