defmodule MMGO.AtmosphereTest do
  use ExUnit.Case, async: true

  alias MMGO.Atmosphere

  test "derives a stable ambient cue from a persisted location kind" do
    assert %{
             ambient_cue: "city",
             major_event_cue: nil,
             active_cue: "city",
             available?: false,
             label: "городской гул"
           } = Atmosphere.cue_for(%{kind: :city}, assets: %{})

    assert Atmosphere.ambient_cue(:dungeon_entrance) == "dungeon"
    assert Atmosphere.ambient_cue(:unknown_place) == "world"
  end

  test "a configured curated event overrides ambient audio while preserving both semantic cues" do
    state =
      Atmosphere.cue_for(:tower,
        major_event: :combat,
        assets: %{tower: "/audio/tower.ogg", combat: "/audio/combat.ogg"}
      )

    assert state.ambient_cue == "tower"
    assert state.ambient_source == "/audio/tower.ogg"
    assert state.major_event_cue == "combat"
    assert state.event_source == "/audio/combat.ogg"
    assert state.active_cue == "combat"
    assert state.active_source == "/audio/combat.ogg"
    refute state.loop?
    assert state.available?
  end

  test "an unavailable event recording falls back to configured ambience without losing the event signal" do
    state =
      Atmosphere.cue_for(:wilderness,
        major_event: :journey,
        assets: %{wilderness: "/audio/wilderness.ogg"}
      )

    assert state.major_event_cue == "journey"
    assert state.event_source == nil
    assert state.active_cue == "wilderness"
    assert state.active_source == "/audio/wilderness.ogg"
    assert state.loop?
  end

  test "accepts only known local recording paths and never turns arbitrary input into a cue" do
    state =
      Atmosphere.cue_for(:city,
        major_event: "not-a-real-event",
        assets: %{
          city: "https://untrusted.example/city.ogg",
          combat: "//untrusted.example/combat.ogg",
          journey: "/audio/journey.ogg"
        }
      )

    assert state.major_event_cue == nil
    assert state.ambient_source == nil
    refute state.available?
    assert Atmosphere.event_cue("combat") == "combat"
    assert Atmosphere.event_cue("not-a-real-event") == nil
  end
end
