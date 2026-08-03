defmodule MMGOWeb.ErrorHTMLTest do
  use MMGOWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(MMGOWeb.ErrorHTML, "404", "html", []) == "Страница не найдена"
  end

  test "renders 500.html" do
    assert render_to_string(MMGOWeb.ErrorHTML, "500", "html", []) ==
             "Внутренняя ошибка сервера"
  end
end
