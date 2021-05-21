defmodule Karma.StoreAdapter do
  use GenServer
  require Logger

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(state) do
    pid = GenServer.whereis(state)

    if pid, do: {:ok, state}, else: {:error, :not_started}
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

  # MARK: - Implementation
  @impl true
  # @spec handle_call({atom(), boolean(), {binary(), binary()}, {binary(), binary()}}) :: {:ok, any()}
  def handle_call({:store, action, user, room}, _from, state) do
    reply = GenServer.call(state, {:store, action, user, room})
    {:reply, reply, state}
  end
end
