defmodule MMGOWeb.FederationController do
  use MMGOWeb, :controller

  alias MMGO.Federation

  def manifest(conn, _params) do
    manifest = Federation.local_realm!() |> Federation.export_realm_manifest()
    json(conn, manifest)
  end

  def import_migration(conn, params) do
    with :ok <- authorize_import(conn),
         {:ok, response} <- Federation.import_remote_character(params) do
      json(conn, response)
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "unauthorized"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: format_changeset(changeset)})
    end
  end

  defp authorize_import(conn) do
    expected_token = Application.get_env(:mmgo, MMGO.Federation, [])[:import_token]
    auth_header = List.first(get_req_header(conn, "authorization"))

    case {expected_token, auth_header} do
      {nil, _header} ->
        {:error, :unauthorized}

      {"", _header} ->
        {:error, :unauthorized}

      {token, "Bearer " <> provided_token}
      when is_binary(token) and byte_size(token) == byte_size(provided_token) ->
        if Plug.Crypto.secure_compare(token, provided_token),
          do: :ok,
          else: {:error, :unauthorized}

      _other ->
        {:error, :unauthorized}
    end
  end

  defp format_changeset(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
