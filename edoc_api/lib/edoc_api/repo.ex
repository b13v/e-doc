defmodule EdocApi.Repo do
  use Ecto.Repo,
    otp_app: :edoc_api,
    adapter: Ecto.Adapters.Postgres
end
