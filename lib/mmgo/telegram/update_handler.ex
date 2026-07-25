defmodule MMGO.Telegram.UpdateHandler do
  alias MMGO.Accounts
  alias MMGO.Telegram
  alias MMGO.Telegram.{Commands, ReleaseAnnouncements}

  def handle(%{"message" => %{"from" => from} = message, "update_id" => update_id}) do
    with {:ok, %{account: account, character: character}} <-
           Accounts.provision_from_telegram(from),
         {:ok, _response} <- maybe_reply(character, message) do
      {:ok,
       %{
         handled: true,
         update_id: update_id,
         account_id: account.id,
         character_id: character && character.id,
         type: "message"
       }}
    end
  end

  def handle(%{"callback_query" => %{"from" => from}, "update_id" => update_id}) do
    with {:ok, %{account: account, character: character}} <-
           Accounts.provision_from_telegram(from) do
      {:ok,
       %{
         handled: true,
         update_id: update_id,
         account_id: account.id,
         character_id: character && character.id,
         type: "callback_query"
       }}
    end
  end

  def handle(%{"update_id" => update_id}) do
    {:ok, %{handled: false, update_id: update_id, reason: :unsupported_update}}
  end

  def handle(_update), do: {:error, :invalid_update}

  defp maybe_reply(character, %{"chat" => %{"id" => chat_id}} = message) do
    case command_response(character, message) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, response_text} when is_binary(response_text) ->
        Telegram.send_message(chat_id, response_text, reply_options(message))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_reply(_character, _message), do: {:ok, nil}

  defp command_response(character, message) do
    case ReleaseAnnouncements.process_message(message) do
      {:ok, nil} -> Commands.process_message(character, message)
      response -> response
    end
  end

  defp reply_options(%{"text" => text}) when is_binary(text) do
    command =
      text
      |> String.trim()
      |> String.split(~r/\s+/, parts: 2)
      |> List.first()
      |> to_string()
      |> String.trim_leading("/")
      |> String.split("@")
      |> List.first()
      |> String.downcase()

    case {command, Telegram.mini_app_url()} do
      {command, url}
      when command in [
             "start",
             "play",
             "help",
             "status",
             "inventory",
             "routes",
             "journey",
             "spells"
           ] and
             is_binary(url) ->
        [
          reply_markup: %{
            inline_keyboard: [
              [%{text: "Открыть MMGO", web_app: %{url: url}}]
            ]
          }
        ]

      _other ->
        []
    end
  end

  defp reply_options(_message), do: []
end
