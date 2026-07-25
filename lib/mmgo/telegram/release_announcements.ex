defmodule MMGO.Telegram.ReleaseAnnouncements do
  @moduledoc """
  Owns the single Telegram destination used for release announcements.

  Only the configured Telegram administrator may change the destination.
  The destination is durable so deployments and application restarts do not
  require environment-file edits.
  """

  alias MMGO.Repo
  alias MMGO.Telegram
  alias MMGO.Telegram.ReleaseChannel

  @channel_key "release_updates"
  @max_chat_id 9_223_372_036_854_775_807

  def process_message(%{"text" => text} = message) when is_binary(text) do
    case parse_command(text) do
      {:ok, "updates_here", []} ->
        configure_current_chat(message)

      {:ok, "updates_chat", [chat_id]} ->
        configure_explicit_chat(message, chat_id)

      {:ok, "updates_status", []} ->
        status(message)

      {:ok, command, _args} when command in ["updates_here", "updates_chat", "updates_status"] ->
        authorize(message, fn ->
          {:ok,
           "Команды обновлений:\n/updates_here — использовать текущий чат\n/updates_chat <chat_id> — указать ID\n/updates_status — показать настройку"}
        end)

      _other ->
        {:ok, nil}
    end
  end

  def process_message(_message), do: {:ok, nil}

  def current_channel do
    Repo.get_by(ReleaseChannel, key: @channel_key)
  end

  def announce_release(version, source_sha, public_url)
      when is_binary(version) and is_binary(source_sha) and is_binary(public_url) do
    case current_channel() do
      nil ->
        {:ok, :not_configured}

      channel ->
        text =
          [
            "🪄 MMGO обновлён",
            "Версия: #{version}",
            "Коммит: #{String.slice(source_sha, 0, 12)}",
            "Открыть игру: #{public_url}"
          ]
          |> Enum.join("\n")

        Telegram.send_message(channel.chat_id, text, disable_web_page_preview: true)
    end
  end

  defp configure_current_chat(message) do
    authorize(message, fn ->
      with %{"id" => chat_id} = chat <- Map.get(message, "chat"),
           true <- valid_chat_id?(chat_id),
           {:ok, _channel} <- put_channel(chat_id, chat["title"], admin_user_id()) do
        {:ok, "Этот чат (#{chat_id}) будет получать сообщения об обновлениях MMGO."}
      else
        _error -> {:ok, "Не удалось определить ID текущего чата."}
      end
    end)
  end

  defp configure_explicit_chat(message, raw_chat_id) do
    authorize(message, fn ->
      case parse_chat_id(raw_chat_id) do
        {:ok, chat_id} ->
          case put_channel(chat_id, nil, admin_user_id()) do
            {:ok, _channel} ->
              {:ok, "Чат #{chat_id} будет получать сообщения об обновлениях MMGO."}

            {:error, _changeset} ->
              {:ok, "Не удалось сохранить ID чата."}
          end

        :error ->
          {:ok, "ID чата должен быть целым числом, например -1001234567890."}
      end
    end)
  end

  defp status(message) do
    authorize(message, fn ->
      case current_channel() do
        nil ->
          {:ok, "Чат обновлений пока не назначен. Используйте /updates_here в нужном чате."}

        channel ->
          title = if channel.chat_title in [nil, ""], do: "", else: " · #{channel.chat_title}"
          {:ok, "Обновления отправляются в чат #{channel.chat_id}#{title}."}
      end
    end)
  end

  defp authorize(%{"from" => %{"id" => user_id}}, callback)
       when is_function(callback, 0) do
    if user_id == admin_user_id() do
      callback.()
    else
      {:ok, "Эта команда доступна только владельцу MMGO."}
    end
  end

  defp authorize(_message, _callback), do: {:ok, "Не удалось подтвердить владельца команды."}

  defp put_channel(chat_id, chat_title, configured_by) do
    attrs = %{
      key: @channel_key,
      chat_id: chat_id,
      chat_title: chat_title,
      configured_by_telegram_user_id: configured_by
    }

    %ReleaseChannel{}
    |> ReleaseChannel.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          chat_id: chat_id,
          chat_title: chat_title,
          configured_by_telegram_user_id: configured_by,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :key,
      returning: true
    )
  end

  defp parse_command(text) do
    text = String.trim(text)

    if String.starts_with?(text, "/") do
      [raw_command | args] = String.split(text, ~r/\s+/, trim: true)

      command =
        raw_command
        |> String.trim_leading("/")
        |> String.split("@")
        |> List.first()
        |> String.downcase()

      {:ok, command, args}
    else
      :ignore
    end
  end

  defp parse_chat_id(raw_chat_id) do
    case Integer.parse(raw_chat_id) do
      {chat_id, ""} when chat_id != 0 and abs(chat_id) <= @max_chat_id -> {:ok, chat_id}
      _other -> :error
    end
  end

  defp valid_chat_id?(chat_id) do
    is_integer(chat_id) and chat_id != 0 and abs(chat_id) <= @max_chat_id
  end

  defp admin_user_id do
    Application.get_env(:mmgo, Telegram, [])[:release_admin_user_id]
  end
end
