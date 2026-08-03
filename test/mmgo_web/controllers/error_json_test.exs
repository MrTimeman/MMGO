defmodule MMGOWeb.ErrorJSONTest do
  use MMGOWeb.ConnCase, async: true

  test "renders 404" do
    assert MMGOWeb.ErrorJSON.render("404.json", %{}) ==
             %{errors: %{detail: "Страница не найдена"}}
  end

  test "renders 500" do
    assert MMGOWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Внутренняя ошибка сервера"}}
  end
end
