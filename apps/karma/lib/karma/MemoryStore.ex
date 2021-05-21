defmodule Karma.MemoryStore do
  use GenServer
  require Logger

  def start_link(state \\ %{}) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  @spec init(nil | map()) :: {:ok, map()}
  def init(state \\ %{})

  def init(state) when is_map(state) do
    {:ok, state}
  end

  def init(state) when state == nil, do: init()

  @impl true
  def handle_call({:store, action, {_name, name_id}, {room, _room_id}}, _from, state) do
    room_store = Map.get(state, room, %{})

    karma =
      room_store
      |> Map.get(name_id, 0)

    karma = if action, do: karma + 1, else: karma - 1

    room_store = Map.put(room_store, name_id, karma)
    state = Map.put(state, room, room_store)

    {:reply, karma, state}
  end
end
