defmodule MMGO.Notifications.Formatter do
  alias MMGO.Notifications.Notification

  def render(%Notification{kind: "journey_arrived", payload: payload}) do
    {:ok,
     %{
       text:
         "Your journey is complete. You have arrived at location ##{payload["to_location_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "academy_completed", payload: payload}) do
    track_suffix =
      case payload["track"] do
        nil -> ""
        track -> " Track: #{track}."
      end

    {:ok,
     %{
       text: "Your #{payload["program_type"]} enrollment is complete.#{track_suffix}",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "scavenge_completed", payload: payload}) do
    {:ok,
     %{
       text:
         "Scavenging complete. Yield: #{payload["quantity_yielded"]} unit(s). Attempt ##{payload["attempt_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "brew_completed", payload: payload}) do
    {:ok,
     %{
       text:
         "Brewing complete. Yield: #{payload["yielded_quantity"]} unit(s). Brew job ##{payload["brew_job_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "craft_completed", payload: payload}) do
    {:ok,
     %{
       text:
         "Crafting complete. Yield: #{payload["yielded_quantity"]} unit(s). Craft job ##{payload["craft_job_id"]}.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{kind: "base_ready", payload: payload}) do
    {:ok,
     %{
       text:
         "Base ready. Base ##{payload["base_id"]} at location ##{payload["location_id"]} is now active.",
       opts: [parse_mode: "HTML"]
     }}
  end

  def render(%Notification{}), do: {:error, :unsupported_notification_kind}
end
