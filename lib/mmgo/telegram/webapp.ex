defmodule MMGO.Telegram.WebApp do
  def validate_init_data(init_data, bot_token) when is_binary(init_data) and is_binary(bot_token) do
    params = URI.decode_query(init_data)

    with {:ok, hash} <- Map.fetch(params, "hash"),
         {:ok, data_check_string} <- build_data_check_string(params) do
      secret_key = :crypto.mac(:hmac, :sha256, bot_token, "WebAppData")
      computed = :crypto.mac(:hmac, :sha256, secret_key, data_check_string)
      computed_hex = Base.encode16(computed, case: :lower)

      if Plug.Crypto.secure_compare(computed_hex, hash) do
        user_json = Map.get(params, "user")
        parse_user(user_json)
      else
        {:error, :invalid_hash}
      end
    else
      :error -> {:error, :missing_hash}
      {:error, _reason} = error -> error
    end
  end

  defp build_data_check_string(params) do
    params
    |> Map.delete("hash")
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      case value do
        v when is_binary(v) -> {:cont, {:ok, [acc, "#{key}=#{v}" | []]}}
        _ -> {:halt, {:error, {:invalid_param_type, key}}}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, parts |> List.flatten() |> Enum.join("\n")}
      error -> error
    end
  end

  defp parse_user(nil), do: {:error, :missing_user}

  defp parse_user(user_json) when is_binary(user_json) do
    case Jason.decode(user_json) do
      {:ok, user} -> {:ok, user}
      _ -> {:error, :invalid_user_json}
    end
  end
end
