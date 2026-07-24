defmodule MMGOWeb.HealthControllerTest do
  use MMGOWeb.ConnCase, async: true

  test "GET /healthz", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/healthz")

    assert %{
             "status" => "ok",
             "application" => "mmgo",
             "version" => _version,
             "checks" => %{"database" => "ready"}
           } =
             json_response(conn, 200)
  end

  test "GET /livez", %{conn: conn} do
    conn = get(conn, ~p"/livez")

    assert %{"status" => "ok", "checks" => %{"process" => "alive"}} =
             json_response(conn, 200)
  end
end
