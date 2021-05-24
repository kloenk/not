defmodule Bot.Distri.Connector do
  use GenServer
  require Logger

  def start_link(arg \\ %{}) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(nil) do
    init(%{})
  end

  def init(config) when is_map(config) do
    env = Application.fetch_env!(:bot, :nodes)

    cfg = %{}

    cfg =
      Map.put(
        cfg,
        :wants,
        if config[:wants] != nil do
          config[:wants]
        else
          env[:nodes]
        end
      )

    cfg = Map.put(cfg, :needs, ceil(length(cfg[:wants]) * 0.51))
    cfg = Map.put(cfg, :valid, false)

    # TODO: long running task to connect to lost nodes

    {:ok, cfg}
  end

  # MARK: - Intends
  def get_needs do
    GenServer.call(__MODULE__, {:get_needs})
  end

  def could_save? do
    GenServer.call(__MODULE__, {:could_save})
  end

  def can_save? do
    GenServer.call(__MODULE__, {:can_save})
  end

  def nodes do
    GenServer.call(__MODULE__, {:nodes})
  end

  def wants do
    GenServer.call(__MODULE__, {:wants})
  end

  def is_main(node \\ Node.self()) do
    GenServer.call(__MODULE__, {:is_main, node})
  end

  def all_connected? do
    GenServer.call(__MODULE__, {:all_connected})
  end

  def missing do
    GenServer.call(__MODULE__, {:missing})
  end

  def cache_valid? do
    GenServer.call(__MODULE__, {:valid})
  end

  def find_main() do
    GenServer.call(__MODULE__, {:find_main})
  end

  def set_valid(action) when is_boolean(action) do
    GenServer.cast(__MODULE__, {:valid, action})
  end

  # MARK: - Implementation
  @impl true
  def handle_call({:get_needs}, _from, state) do
    {:reply, state[:needs], state}
  end

  @impl true
  def handle_call({:could_save}, _from, state) do
    x = length(Node.list()) + 1 >= state[:needs]
    {:reply, x, state}
  end

  @impl true
  def handle_call({:can_save}, _from, state) do
    x = length(Node.list()) + 1 >= state[:needs]
    x = x && state[:valid]
    {:reply, x, state}
  end

  @impl true
  def handle_call({:wants}, _from, state) do
    nodes =
      state[:wants]
      |> Enum.filter(&(&1 != Node.self()))

    {:reply, nodes, state}
  end

  @impl true
  def handle_call({:nodes}, _from, state) do
    nodes = state[:wants]

    {:reply, nodes, state}
  end

  @impl true
  def handle_call({:is_main, node}, _from, state) do
    x = is_first_connected(state[:wants], node)
    {:reply, x, state}
  end

  @impl true
  def handle_call({:all_connected}, _from, state) do
    x =
      state[:wants]
      |> Enum.filter(&(&1 != Node.self()))
      |> missing(Node.list())

    x = x == []
    {:reply, x, state}
  end

  @impl true
  def handle_call({:missing}, _from, state) do
    x =
      state[:wants]
      |> Enum.filter(&(&1 != Node.self()))
      |> missing(Node.list())

    {:reply, x, state}
  end

  @impl true
  def handle_call({:valid}, _from, state) do
    {:reply, state[:valid], state}
  end

  @impl true
  def handle_call({:find_main}, _from, state) do
    x = :todo
    {:reply, x, state}
  end

  @impl true
  def handle_cast({:valid, action}, state) do
    state = Map.put(state, :valid, action)
    {:noreply, state}
  end

  # MARK: - Private
  defp is_first_connected(list, connected \\ Node.list() ++ [Node.self()], node)

  defp is_first_connected([head | tail], connected, node) do
    list = connected |> Enum.map(&(&1 == head)) |> Enum.filter(& &1)

    if list == [] do
      is_first_connected(tail, connected, node)
    else
      head == node
    end
  end

  defp is_first_connected([], _connected, _node), do: false

  defp missing([head | tail], connected) do
    contains = connected |> Enum.map(&(&1 == head)) |> Enum.filter(& &1)

    if contains == [] do
      [head] ++ missing(tail, connected)
    else
      missing(tail, connected)
    end
  end

  defp missing([], _connected), do: []
end
