defmodule MMGO.Telegram.UpdateHandler do
  alias MMGO.Accounts
  alias MMGO.Accounts.CharacterProfiles
  alias MMGO.Play
  alias MMGO.Telegram
  alias MMGO.Telegram.{Client, Commands, ReleaseAnnouncements}

  def handle(%{"message" => %{"from" => from} = message, "update_id" => update_id}) do
    with {:ok, %{account: account}} <- Accounts.provision_from_telegram(from),
         character <- Accounts.get_default_world_character_for_account(account.id),
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

  def handle(%{"callback_query" => %{"from" => from} = callback_query, "update_id" => update_id}) do
    with {:ok, %{account: account}} <- Accounts.provision_from_telegram(from) do
      character = Accounts.get_default_world_character_for_account(account.id)

      callback_result =
        if world_character_ready?(character) do
          process_callback(character, callback_query)
        else
          choose_mode_callback()
        end

      _ = answer_callback_query(callback_query, callback_result)

      {:ok,
       %{
         handled: true,
         update_id: update_id,
         account_id: account.id,
         character_id: character && character.id,
         type: "callback_query",
         callback_result: callback_result
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
      {:ok, nil} -> maybe_process_game_command(character, message)
      response -> response
    end
  end

  defp maybe_process_game_command(character, message) do
    if world_character_ready?(character) do
      Commands.process_message(character, message)
    else
      pre_mode_response(message)
    end
  end

  defp pre_mode_response(%{"text" => text}) when is_binary(text) do
    case command_name(text) do
      "start" ->
        {:ok,
         "Добро пожаловать в MMGO. Откройте Mini App и выберите путь: общий мир или Арену. До выбора мы не создаём инвентарь и не запускаем прогресс мира."}

      "play" ->
        {:ok, "Открываю выбор режима MMGO. Продолжите кнопкой ниже."}

      "help" ->
        {:ok,
         "Сначала выберите режим в Mini App: общий мир MMGO или боевую Арену. После выбора команды мира станут доступны вашему мировому персонажу."}

      nil ->
        {:ok, nil}

      _command ->
        {:ok, "Сначала откройте Mini App и выберите общий мир или Арену."}
    end
  end

  defp pre_mode_response(_message), do: {:ok, nil}

  defp command_name(text) do
    text = String.trim(text)

    if String.starts_with?(text, "/") do
      text
      |> String.split(~r/\s+/, parts: 2)
      |> List.first()
      |> String.trim_leading("/")
      |> String.split("@")
      |> List.first()
      |> String.downcase()
    end
  end

  defp world_character_ready?(nil), do: false

  defp world_character_ready?(character) do
    character.status == :active and not CharacterProfiles.arena?(character) and
      not CharacterProfiles.sealed_spirit?(character)
  end

  defp choose_mode_callback do
    %{ok?: false, message: "Сначала откройте Mini App и выберите режим игры."}
  end

  defp process_callback(character, %{"data" => "road:accept:" <> encounter_id}) do
    respond_to_traveler_contact(character, encounter_id, "accept")
  end

  defp process_callback(character, %{"data" => "road:reject:" <> encounter_id}) do
    respond_to_traveler_contact(character, encounter_id, "decline")
  end

  defp process_callback(_character, _callback_query) do
    %{ok?: false, message: "Это действие больше недоступно."}
  end

  defp respond_to_traveler_contact(character, encounter_id, decision) do
    case Play.respond_to_traveler_contact(character, encounter_id, decision) do
      {:ok, _result} when decision == "accept" ->
        %{
          ok?: true,
          message: "Запрос принят. Контакты придут отдельным сообщением."
        }

      {:ok, _result} ->
        %{ok?: true, message: "Запрос отклонён. Контакты не раскрыты."}

      {:error, _reason} ->
        %{ok?: false, message: "Этот запрос уже недоступен."}
    end
  end

  defp answer_callback_query(%{"id" => callback_query_id}, %{message: message})
       when is_binary(callback_query_id) do
    Client.answer_callback_query(callback_query_id, text: message)
  end

  defp answer_callback_query(_callback_query, _result), do: {:ok, nil}

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
