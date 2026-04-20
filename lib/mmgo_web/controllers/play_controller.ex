defmodule MMGOWeb.PlayController do
  use MMGOWeb, :controller

  def show(conn, _params) do
    render(conn, :show, page_title: "Realm Atlas")
  end
end
