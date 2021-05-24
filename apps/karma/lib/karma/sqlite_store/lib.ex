defmodule Karma.SqliteStore do
  use GenServer
  require Logger

  def start_link(state \\ %{}) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  def export() do
    GenServer.call(__MODULE__, :export)
  end

  # def import(new) when is_map(new) do
  #  GenServer.call(__MODULE__, {:import, new})
  # end

  @impl true
  def handle_call({:store, action, {_name, name_id}, {room, _room_id}}, _from, state) do
    karma = Karma.SqliteStore.Karma.inc_check(room, name_id, if(action, do: 1, else: -1))

    {:reply, karma, state}
  end

  @impl true
  def handle_call({:store, action, {_name, name_id}, {room, _room_id}, symbol}, _from, state) do
    karma = Karma.SqliteStore.Karma.inc_check(room, name_id, if(action, do: 1, else: -1), symbol)

    {:reply, karma, state}
  end

  @impl true
  def handle_call(:export, _from, state) do
    {:reply, Karma.SqliteStore.Karma.all(), state}
  end

  @impl true
  def handle_cast({:set, id, room, user, karma, emoji}, state) do
    row = %Karma.SqliteStore.Karma{
      id: id,
      room: room,
      user: user,
      # karma: karma,
      symbol: emoji
    }

    Karma.SqliteStore.Repo.delete(row)

    row = %Karma.SqliteStore.Karma{
      id: id,
      room: room,
      user: user,
      karma: karma,
      symbol: emoji
    }

    Karma.SqliteStore.Repo.insert(row)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send, node}, state) do
    data = Karma.SqliteStore.Karma.all()
    # data = "abc"
    # send({Karma.SqliteStore, node}, {:receive, data})
    send({Bot.Distri.Connector.CTask, node}, {:receive_data, data, Node.self()})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:receive, data}, state) do
    Karma.SqliteStore.Repo.delete_all(Karma.SqliteStore.Karma)
    import_data(data)
    {:noreply, state}
  end

  # TODO: better import
  def import_data([head | tail]) do
    Karma.SqliteStore.Repo.insert!(head)
    import_data(tail)
  end

  def import_data([]), do: nil
end
