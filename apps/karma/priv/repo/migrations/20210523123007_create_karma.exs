defmodule Karma.SqliteStore.Repo.Migrations.CreateKarma do
  use Ecto.Migration

  def change do
    create table(:karma) do
      add :room, :string
      add :user, :string
      add :karma, :integer
      add :symbol, :string
    end
  end
end
