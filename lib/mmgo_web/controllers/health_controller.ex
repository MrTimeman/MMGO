defmodule MMGOWeb.HealthController do
  use MMGOWeb, :controller

  alias MMGO.Repo

  def show(conn, _params) do
    case Repo.query("SELECT 1", [], timeout: 2_000) do
      {:ok, _result} ->
        json(conn, health_payload("ok", %{database: "ready"}))

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(health_payload("degraded", %{database: "unavailable"}))
    end
  end

  def live(conn, _params), do: json(conn, health_payload("ok", %{process: "alive"}))

  defp health_payload(status, checks) do
    %{
      status: status,
      application: "mmgo",
      version: Application.spec(:mmgo, :vsn) |> to_string(),
      checks: checks
    }
  end
end
