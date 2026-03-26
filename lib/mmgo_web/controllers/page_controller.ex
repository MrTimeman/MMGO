defmodule MMGOWeb.PageController do
  use MMGOWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Ministry of MaGic Online")
  end
end
