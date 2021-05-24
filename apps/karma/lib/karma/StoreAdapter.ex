defmodule Karma.StoreAdapter do
  use GenServer
  require Logger

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(state) do
    pid = GenServer.whereis(state)

    if pid do
      {:ok, %{server: state, connector: nil}}
    else
      {:error, :not_started}
    end
  end

  # MARK: - Public interface
  def store(action, user, room) do
    if GenServer.whereis(__MODULE__) != nil do
      GenServer.call(__MODULE__, {:store, action, user, room})
    else
      Logger.warn("no StoreAdapter started yet")
      0
    end
  end

  def set({id, room, user, karma, emoji}) do
    if GenServer.whereis(__MODULE__) != nil do
      GenServer.cast(__MODULE__, {:set, id, room, user, karma, emoji})
    else
      Logger.warn("no StoreAdapter started yet")
      0
    end
  end

  def register_connector(pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:reg_connector, pid})
  end

  # MARK: - Implementation
  @impl true
  # @spec handle_call({atom(), boolean(), {binary(), binary()}, {binary(), binary()}}) :: {:ok, any()}
  def handle_call({:store, action, user, room}, _from, state) do
    {id, reply} = GenServer.call(state[:server], {:store, action, user, room})

    if state[:connector] != nil do
      {room, _room_id} = room
      {_name, name_id} = user
      {}
      send(state[:connector], {:set_out, id, room, name_id, reply, nil})
    end

    {:reply, reply, state}
  end

  def handle_cast({:set, id, room, user, karma, emoji}, state) do
    GenServer.cast(state[:server], {:set, id, room, user, karma, emoji})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send, node}, state) do
    GenServer.cast(state[:server], {:send, node})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:receive, data}, state) do
    GenServer.cast(state[:server], {:receive, data})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:reg_connector, pid}, state) do
    state = Map.put(state, :connector, pid)
    {:noreply, state}
  end
end
