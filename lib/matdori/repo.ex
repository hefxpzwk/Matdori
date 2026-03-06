defmodule Matdori.Repo do
  use Ecto.Repo,
    otp_app: :matdori,
    adapter: Ecto.Adapters.Postgres
end
