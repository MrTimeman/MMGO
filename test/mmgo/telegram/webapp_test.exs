defmodule MMGO.Telegram.WebAppTest do
  use ExUnit.Case, async: true

  alias MMGO.Telegram.WebApp

  @bot_token "123456:test-token"
  @user %{
    "id" => 1_265_881_543,
    "first_name" => "Альберт",
    "last_name" => "Латыпов",
    "username" => "MrTimeman",
    "language_code" => "en"
  }

  test "validate_init_data/2 accepts Telegram WebApp signed init data" do
    init_data = signed_init_data(@bot_token)

    assert {:ok, user} = WebApp.validate_init_data(init_data, @bot_token)
    assert user["id"] == @user["id"]
    assert user["username"] == "MrTimeman"
  end

  test "validate_init_data/2 rejects data signed for another bot token" do
    init_data = signed_init_data(@bot_token)

    assert {:error, :invalid_hash} = WebApp.validate_init_data(init_data, "wrong-token")
  end

  defp signed_init_data(bot_token) do
    params = %{
      "auth_date" => "1778000515",
      "query_id" => "AAHH0XNLAAAAAMfRc0vCW6z1",
      "signature" => "telegram-ed25519-signature",
      "user" => Jason.encode!(@user)
    }

    hash =
      params
      |> data_check_string()
      |> signed_hash(bot_token)

    params
    |> Map.put("hash", hash)
    |> URI.encode_query()
  end

  defp data_check_string(params) do
    params
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp signed_hash(data_check_string, bot_token) do
    secret_key = :crypto.mac(:hmac, :sha256, "WebAppData", bot_token)

    :hmac
    |> :crypto.mac(:sha256, secret_key, data_check_string)
    |> Base.encode16(case: :lower)
  end
end
