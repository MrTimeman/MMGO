defmodule MMGO.Telegram.WebAppAuthTest do
  use ExUnit.Case, async: true

  alias MMGO.Telegram.WebAppAuth

  @bot_token "test-bot-token"
  @now ~U[2026-07-09 12:00:00Z]

  test "authenticates a valid signed Mini App user" do
    assert {:ok, user} =
             WebAppAuth.authenticate(signed_init_data(), bot_token: @bot_token, now: @now)

    assert user["id"] == 101_001
    assert user["username"] == "towerwalker"
  end

  test "rejects a tampered signed field" do
    init_data = signed_init_data() |> String.replace("Tower", "Impostor")

    assert {:error, :invalid_hash} =
             WebAppAuth.authenticate(init_data, bot_token: @bot_token, now: @now)
  end

  test "rejects expired and future auth dates" do
    expired = signed_init_data(%{"auth_date" => Integer.to_string(DateTime.to_unix(@now) - 301)})
    future = signed_init_data(%{"auth_date" => Integer.to_string(DateTime.to_unix(@now) + 1)})

    assert {:error, :expired_auth_date} =
             WebAppAuth.authenticate(expired, bot_token: @bot_token, now: @now)

    assert {:error, :expired_auth_date} =
             WebAppAuth.authenticate(future, bot_token: @bot_token, now: @now)
  end

  test "rejects missing hash, auth date, and bot token" do
    assert {:error, :missing_hash} =
             WebAppAuth.authenticate(unsigned_init_data(), bot_token: @bot_token, now: @now)

    assert {:error, :missing_auth_date} =
             WebAppAuth.authenticate(
               signed_init_data(%{"auth_date" => nil}),
               bot_token: @bot_token,
               now: @now
             )

    assert {:error, :missing_bot_token} =
             WebAppAuth.authenticate(signed_init_data(), bot_token: nil, now: @now)
  end

  test "rejects malformed user data even when the signature is valid" do
    init_data = signed_init_data(%{"user" => "{not-json"})

    assert {:error, :invalid_user} =
             WebAppAuth.authenticate(init_data, bot_token: @bot_token, now: @now)
  end

  defp signed_init_data(overrides \\ %{}) do
    fields = fields(overrides)
    URI.encode_query(Map.put(fields, "hash", expected_hash(fields)))
  end

  defp unsigned_init_data, do: URI.encode_query(fields(%{}))

  defp fields(overrides) do
    %{
      "auth_date" => Integer.to_string(DateTime.to_unix(@now)),
      "query_id" => "AAEAAA",
      "user" =>
        Jason.encode!(%{
          "id" => 101_001,
          "first_name" => "Tower",
          "username" => "towerwalker",
          "language_code" => "ru"
        })
    }
    |> Map.merge(overrides)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp expected_hash(fields) do
    secret_key = :crypto.mac(:hmac, :sha256, @bot_token, "WebAppData")

    fields
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)
    |> then(&:crypto.mac(:hmac, :sha256, secret_key, &1))
    |> Base.encode16(case: :lower)
  end
end
