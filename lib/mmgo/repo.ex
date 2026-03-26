defmodule MMGO.Repo do
  use Ecto.Repo,
    otp_app: :mmgo,
    adapter: Ecto.Adapters.Postgres
end
