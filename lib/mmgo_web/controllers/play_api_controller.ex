defmodule MMGOWeb.PlayApiController do
  use MMGOWeb, :controller

  alias MMGO.Accounts
  alias MMGO.Play
  alias MMGOWeb.PlaySession

  def state(conn, _params) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, state} <- Play.map_state(character) do
      json(conn, %{ok: true, state: state})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def create_journey(conn, %{"route_id" => route_id}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, _result} <- Play.start_journey(character, route_id),
         {:ok, state} <- Play.map_state(character) do
      json(conn, %{ok: true, state: state})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def create_journey(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      ok: false,
      error: "validation_failed",
      details: %{"route_id" => ["route_id is required"]}
    })
  end

  def create_journey_plan(conn, %{"route_ids" => route_ids}) when is_list(route_ids) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, _result} <- Play.start_journey_plan(character, route_ids),
         {:ok, state} <- Play.map_state(character) do
      json(conn, %{ok: true, state: state})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def create_journey_plan(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      ok: false,
      error: "validation_failed",
      details: %{"route_ids" => ["route_ids is required"]}
    })
  end

  def telegram_session(conn, %{"init_data" => init_data}) when is_binary(init_data) do
    with {:ok, user} <- verify_telegram_init_data(init_data),
         {:ok, %{character: character}} <- Accounts.provision_from_telegram(user),
         {:ok, conn, character} <- PlaySession.bind_character(conn, character) do
      json(conn, %{
        ok: true,
        character: %{id: character.id, name: character.name, level: character.level}
      })
    else
      {:error, :missing_bot_token} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{ok: false, error: "telegram_bot_token_missing"})

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def telegram_session(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: "init_data is required"})
  end

  def cast_utility_spell(conn, %{"spell_id" => spell_id}) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, _spell} <- Play.cast_utility_spell(character, spell_id),
         {:ok, state} <- Play.map_state(character) do
      json(conn, %{ok: true, state: state})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  def cast_utility_spell(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      ok: false,
      error: "validation_failed",
      details: %{"spell_id" => ["spell_id is required"]}
    })
  end

  def fast_arrive(conn, _params) do
    with {:ok, conn, character} <- PlaySession.fetch_current_character(conn),
         {:ok, arrived_character} <- Play.fast_arrive(character),
         {:ok, state} <- Play.map_state(arrived_character) do
      json(conn, %{ok: true, state: state})
    else
      {:error, :no_active_journey} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "no active journey"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "validation_failed", details: format_changeset(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: to_string(reason)})
    end
  end

  defp format_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp verify_telegram_init_data(init_data) do
    with {:ok, token} <- telegram_bot_token(),
         {:ok, params} <- decode_init_data(init_data),
         {:ok, received_hash} <- fetch_required(params, "hash"),
         true <- secure_hash_match?(token, params, received_hash),
         {:ok, user_json} <- fetch_required(params, "user"),
         {:ok, user} <- Jason.decode(user_json) do
      {:ok, user}
    else
      false -> {:error, :invalid_hash}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_init_data}
    end
  end

  defp telegram_bot_token do
    case Application.get_env(:mmgo, :telegram, [])[:bot_token] ||
           System.get_env("TELEGRAM_BOT_TOKEN") do
      token when is_binary(token) and token != "" -> {:ok, token}
      _other -> {:error, :missing_bot_token}
    end
  end

  defp decode_init_data(init_data) do
    params =
      init_data
      |> URI.decode_query()
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    if map_size(params) == 0, do: {:error, :invalid_init_data}, else: {:ok, params}
  rescue
    _ -> {:error, :invalid_init_data}
  end

  defp fetch_required(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :invalid_init_data}
    end
  end

  defp secure_hash_match?(token, params, received_hash) do
    data_check_string =
      params
      |> Map.delete("hash")
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)

    secret = :crypto.mac(:hmac, :sha256, "WebAppData", token)

    expected =
      :crypto.mac(:hmac, :sha256, secret, data_check_string) |> Base.encode16(case: :lower)

    Plug.Crypto.secure_compare(expected, String.downcase(received_hash))
  rescue
    _ -> false
  end
end
