defmodule MMGOWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  def render(template, _assigns) do
    %{errors: %{detail: status_message(template)}}
  end

  defp status_message("400" <> _extension), do: "Некорректный запрос"
  defp status_message("401" <> _extension), do: "Требуется авторизация"
  defp status_message("403" <> _extension), do: "Доступ запрещён"
  defp status_message("404" <> _extension), do: "Страница не найдена"
  defp status_message("405" <> _extension), do: "Недопустимый способ запроса"
  defp status_message("408" <> _extension), do: "Время ожидания истекло"
  defp status_message("409" <> _extension), do: "Конфликт данных"
  defp status_message("410" <> _extension), do: "Страница больше недоступна"
  defp status_message("422" <> _extension), do: "Запрос не удалось обработать"
  defp status_message("429" <> _extension), do: "Слишком много запросов"
  defp status_message("500" <> _extension), do: "Внутренняя ошибка сервера"
  defp status_message("502" <> _extension), do: "Ошибка ответа сервера"
  defp status_message("503" <> _extension), do: "Сервис временно недоступен"
  defp status_message("504" <> _extension), do: "Сервер не ответил вовремя"
  defp status_message(_template), do: "Ошибка запроса"
end
