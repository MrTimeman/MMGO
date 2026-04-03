defmodule MMGOWeb.TelegramEntryLive do
  use MMGOWeb, :live_view

  alias MMGO.Accounts

  @impl true
  def mount(params, session, socket) do
    entry_payload = merge_entry_payload(session, params)
    {:ok, entry} = Accounts.restore_telegram_entry(entry_payload, session: session)

    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> assign(:page_title, "MMGO Entry")
     |> assign(:entry, entry)
     |> assign(:entry_state, entry.state)}
  end

  @impl true
  def handle_event("retry_bootstrap", _params, socket) do
    {:noreply, socket}
  end

  defp heading_for(:first_open), do: "A new realm opens."
  defp heading_for(:resume), do: "Your journey remembers you."
  defp heading_for(:deep_link), do: "A summons awaits."
  defp heading_for(:recovery), do: "The gate lost your trail."

  defp body_copy_for(:first_open),
    do: "Confirm your traveler identity, review your first character, and step into the realm."

  defp body_copy_for(:resume),
    do:
      "Your account link is intact. Review your character and return to the world without another setup step."

  defp body_copy_for(:deep_link),
    do:
      "A Telegram prompt brought you back with a specific destination in mind. Continue directly once the gate is clear."

  defp body_copy_for(:recovery),
    do:
      "MMGO could not match this browser visit to a Telegram identity. Retry from Telegram or reopen the bot fallback."

  defp realm_name(%{realm: %{name: name}}) when is_binary(name), do: name
  defp realm_name(_entry), do: "Canonical Realm"

  defp account_name(%{account: %{display_name: display_name}}) when is_binary(display_name),
    do: display_name

  defp account_name(_entry), do: "Unknown Traveler"

  defp character_name(%{character: %{name: name}}) when is_binary(name), do: name
  defp character_name(_entry), do: "Unbound Wanderer"

  defp recovery_title(%{recovery: %{title: title}}) when is_binary(title), do: title
  defp recovery_title(_entry), do: "We couldn't restore your traveler seal."

  defp recovery_body(%{recovery: %{body: body}}) when is_binary(body), do: body

  defp recovery_body(_entry),
    do: "Try again from Telegram, or reopen MMGO from the bot to refresh your link."

  defp format_target(target) when is_binary(target), do: target

  defp format_target(target) when is_map(target),
    do:
      Map.get(target, :label) || Map.get(target, "label") || Map.get(target, "target") ||
        "linked destination"

  defp format_target(_target), do: "linked destination"

  defp merge_entry_payload(session, params) when is_map(params) do
    session
    |> Map.get("telegram_entry", %{})
    |> Map.merge(params)
  end

  defp merge_entry_payload(session, _params) do
    Map.get(session, "telegram_entry", %{})
  end
end
