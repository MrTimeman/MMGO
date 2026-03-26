defmodule MMGOWeb.HealthControllerTest do
  use MMGOWeb.ConnCase, async: true

  test "GET /healthz", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/healthz")

    assert %{"status" => "ok", "application" => "mmgo", "version" => _version} =
             json_response(conn, 200)
  end
end
