defmodule Karma.SqliteStore.Karma do
  use Ecto.Schema
  require Ecto.Query

  schema "karma" do
    field(:room, :string)
    field(:user, :string)
    field(:karma, :integer)
    field(:symbol, :string)
  end

  def changeset(karma, params \\ %{}) do
    karma
    |> Ecto.Changeset.cast(params, [:room, :user, :karma, :symbol])
    |> Ecto.Changeset.validate_required([:room, :user, :karma])
  end

  def inc(room, user, by \\ 1) do
    Karma.SqliteStore.Karma
    |> Ecto.Query.where([p], p.room == ^room and p.user == ^user and is_nil(p.symbol))
    |> Karma.SqliteStore.Repo.update_all(inc: [karma: by])
  end

  def inc(room, user, by, symbol) do
    Karma.SqliteStore.Karma
    |> Ecto.Query.where([p], p.room == ^room and p.user == ^user and p.symbol == ^symbol)
    |> Karma.SqliteStore.Repo.update_all(inc: [karma: by])
  end

  def inc_check(room, user, by \\ 1) do
    list = Karma.SqliteStore.Karma.find(room, user)

    if list == [] do
      create(room, user, by)
    else
      inc(room, user, by)
    end

    reply = hd(find(room, user))
    {reply.id, reply.karma}
  end

  def inc_check(room, user, by, symbol) do
    list = Karma.SqliteStore.Karma.find(room, user, symbol)

    if list == [] do
      create(room, user, by, symbol)
    else
      inc(room, user, by, symbol)
    end

    hd(find(room, user, symbol)).karma
  end

  def create(room, user, karma \\ 1) do
    %Karma.SqliteStore.Karma{room: room, user: user, karma: karma}
    |> Karma.SqliteStore.Karma.changeset(%{})
    |> Karma.SqliteStore.Repo.insert()
  end

  def create(room, user, karma, symbol) do
    %Karma.SqliteStore.Karma{room: room, user: user, karma: karma, symbol: symbol}
    |> Karma.SqliteStore.Karma.changeset(%{})
    |> Karma.SqliteStore.Repo.insert()
  end

  def find(room, user) do
    Karma.SqliteStore.Karma
    |> Ecto.Query.where([p], p.room == ^room and p.user == ^user and is_nil(p.symbol))
    |> Karma.SqliteStore.Repo.all()
  end

  def find(room, user, symbol) do
    Karma.SqliteStore.Karma
    |> Ecto.Query.where([p], p.room == ^room and p.user == ^user and p.symbol == ^symbol)
    |> Karma.SqliteStore.Repo.all()
  end

  def all(), do: Karma.SqliteStore.Karma |> Karma.SqliteStore.Repo.all()
end
