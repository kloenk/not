defmodule Karma.SqliteStore.Repo do
  use Ecto.Repo,
    otp_app: :karma,
    adapter: Ecto.Adapters.SQLite3
end
