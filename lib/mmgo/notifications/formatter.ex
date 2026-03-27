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

  def render(%Notification{}), do: {:error, :unsupported_notification_kind}
end
