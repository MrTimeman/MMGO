defmodule MMGO.Telegram.WebAppAuth do
  @moduledoc """
  Verifies the signed query string Telegram sends to a Mini App in
  `Telegram.WebApp.initData`.

  The verifier intentionally returns tagged errors and never logs the raw
  init data because it contains an authentication proof and user profile data.
  """

  @default_max_age_seconds 300

  @type authentication_error ::
          :missing_init_data
          | :missing_bot_token
          | :missing_hash
          | :invalid_hash
          | :missing_auth_date
          | :invalid_auth_date
          | :expired_auth_date
          | :missing_user
          | :invalid_user

  @spec authenticate(term(), keyword()) :: {:ok, map()} | {:error, authentication_error()}
  def authenticate(init_data, opts \\ [])

  def authenticate(init_data, opts) when is_binary(init_data) and byte_size(init_data) > 0 do
    with {:ok, bot_token} <- bot_token(opts),
         {:ok, params} <- decode_init_data(init_data),
         {:ok, hash, signed_params} <- extract_hash(params),
         :ok <- verify_hash(bot_token, hash, signed_params),
         {:ok, auth_date} <- auth_date(signed_params),
         :ok <- verify_auth_date(auth_date, now(opts), max_age_seconds(opts)),
         {:ok, user} <- user(signed_params) do
      {:ok, user}
    end
  end

  def authenticate(_init_data, _opts), do: {:error, :missing_init_data}

  defp bot_token(opts) do
    token = Keyword.get(opts, :bot_token, config()[:bot_token])

    if is_binary(token) and byte_size(token) > 0 do
      {:ok, token}
    else
      {:error, :missing_bot_token}
    end
  end

  defp decode_init_data(init_data) do
    {:ok, URI.decode_query(init_data)}
  rescue
    ArgumentError -> {:error, :missing_init_data}
  end

  defp extract_hash(params) do
    case Map.pop(params, "hash") do
      {hash, signed_params} when is_binary(hash) and byte_size(hash) > 0 ->
        {:ok, hash, signed_params}

      _other ->
        {:error, :missing_hash}
    end
  end

  defp verify_hash(bot_token, hash, signed_params) do
    expected_hash = expected_hash(bot_token, signed_params)

    if byte_size(hash) == byte_size(expected_hash) and
         Plug.Crypto.secure_compare(hash, expected_hash) do
      :ok
    else
      {:error, :invalid_hash}
    end
  end

  defp expected_hash(bot_token, signed_params) do
    secret_key = :crypto.mac(:hmac, :sha256, bot_token, "WebAppData")

    signed_params
    |> data_check_string()
    |> then(&:crypto.mac(:hmac, :sha256, secret_key, &1))
    |> Base.encode16(case: :lower)
  end

  defp data_check_string(params) do
    params
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp auth_date(params) do
    case Map.get(params, "auth_date") do
      nil ->
        {:error, :missing_auth_date}

      raw_auth_date when is_binary(raw_auth_date) ->
        case Integer.parse(raw_auth_date) do
          {auth_date, ""} -> {:ok, auth_date}
          _other -> {:error, :invalid_auth_date}
        end

      _other ->
        {:error, :invalid_auth_date}
    end
  end

  defp verify_auth_date(auth_date, now, max_age_seconds)
       when is_integer(auth_date) and is_integer(now) and is_integer(max_age_seconds) do
    age = now - auth_date

    if age >= 0 and age <= max_age_seconds do
      :ok
    else
      {:error, :expired_auth_date}
    end
  end

  defp user(params) do
    case Map.get(params, "user") do
      user_json when is_binary(user_json) ->
        case Jason.decode(user_json) do
          {:ok, %{} = user} -> {:ok, user}
          _other -> {:error, :invalid_user}
        end

      _other ->
        {:error, :missing_user}
    end
  end

  defp now(opts) do
    case Keyword.get(opts, :now, DateTime.utc_now()) do
      %DateTime{} = datetime -> DateTime.to_unix(datetime)
      unix_seconds when is_integer(unix_seconds) -> unix_seconds
      _other -> DateTime.to_unix(DateTime.utc_now())
    end
  end

  defp max_age_seconds(opts) do
    case Keyword.get(opts, :max_age_seconds, config()[:web_app_auth_max_age_seconds]) do
      max_age_seconds when is_integer(max_age_seconds) and max_age_seconds >= 0 -> max_age_seconds
      _other -> @default_max_age_seconds
    end
  end

  defp config, do: Application.get_env(:mmgo, MMGO.Telegram, [])
end
