defmodule MMGO.Telegram.Formatter do
  def datetime(nil), do: "unknown"

  def datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end
end
