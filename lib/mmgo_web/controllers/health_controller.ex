defmodule MMGOWeb.HealthController do
  use MMGOWeb, :controller

  def show(conn, _params) do
    json(conn, %{
      status: "ok",
      application: "mmgo",
      version: Application.spec(:mmgo, :vsn) |> to_string()
    })
  end
end
