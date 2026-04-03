defmodule MMGOWeb.PageController do
  use MMGOWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "MMGO Bootstrap Console")
  end
end
