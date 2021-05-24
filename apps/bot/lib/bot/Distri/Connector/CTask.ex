defmodule Bot.Distri.Connector.CTask do
  use Task, restart: :permanent, id: __MODULE__
  require Logger
  alias Bot.Distri.Connector

  def start_link(arg \\ nil) do
    main = init(arg)

    case main do
      {:error, :nomain} ->
        {:error, :nomain}

      {:ok, main} ->
        {:ok, pid} =
          Task.start_link(__MODULE__, :run_init, [
            %{
              main: main,
              new_nodes: []
            }
          ])

        Process.register(pid, __MODULE__)
        {:ok, pid}
    end
  end

  def init(_arg) do
    # if Node.list() == [] do
    wait_for_genserver(Connector)

    connect_first_main(Connector.nodes())
    |> IO.inspect()

    # else
    #  Logger.warn("Node.list did contain #{inspect Node.list}?")
    #  {:ok, nil}
    # end
  end

  def run_init(state) when is_map(state) do
    node = state[:main]

    wait_for_genserver(Karma.StoreAdapter)
    Karma.StoreAdapter.register_connector(self())

    state =
      if node != nil && node != Node.self() do
        Logger.debug("enslaving at #{inspect(node)}")
        Node.monitor(state[:main], true)
        send({Bot.Distri.Connector.CTask, node}, {:enslave, Node.self()})
        state
      else
        state = Map.put(state, :admin, Node.self())
        Node.list() |> Enum.map(&Node.monitor(&1, true))
        send_out({:taking_main, Node.self()})
        state
      end

    start_trigger()

    connect_after()

    Logger.debug("state after init: #{inspect(state)}")

    run(state)
  end

  def run(state) when is_map(state) do
    state =
      receive do
        v -> handle_info(v, state)
      after
        1000 -> state
      end

    connect_after()

    run(state)
  end

  @spec handle_info(any(), map()) :: map()
  def handle_info(cmd, state)

  def handle_info({:nodedown, node}, state) when is_map(state) do
    Logger.debug("Node #{inspect(node)} is now offline")
    Node.disconnect(node)
    if !Connector.can_save?(), do: Connector.set_valid(false)

    state =
      if state[:main] == node do
        start_trigger()
        Logger.debug("The node #{inspect(node)} was the old main")
        Logger.info("Starting failover")

        state =
          if Connector.is_main() do
            Map.put(state, :main, Node.self())
          else
            state
          end

        state
      else
        state
      end

    state
  end

  def handle_info({:taking_main, node}, state) do
    Node.monitor(node, true)

    if Connector.is_main(node) do
      Logger.debug("#{inspect(node)} is takeing main")

      if Connector.cache_valid?() do
        send({Bot.Distri.Connector.CTask, node}, {:ack, Node.self(), :state})
      else
        send({Bot.Distri.Connector.CTask, node}, {:ack, Node.self()})
      end

      Logger.debug("disable scraper")
      pid = wait_for_pid(Lib.Matrix.Scraper)
      send(pid, {:disable})
      Connector.set_valid(false)

      state
      |> Map.put(:main, node)
    else
      # Logger.warn("#{inspect node} is not main node")
      state
    end
  end

  def handle_info({:ack, node}, state) do
    Logger.debug("#{inspect(node)} accepts main")
    state
  end

  def handle_info({:ack, node, :state}, state) do
    if Connector.cache_valid?() do
      Logger.warn("own cache is also valid")
    else
      Logger.debug("Remote cache is valid on #{inspect(node)}")
      send({Bot.Distri.Connector.CTask, node}, {:request_data, Node.self()})
    end

    state
  end

  def handle_info({:request_data, node}, state) do
    GenServer.cast(Karma.StoreAdapter, {:send, node})
    state
  end

  def handle_info({:receive_data, data, node}, state) do
    IO.inspect(data)
    Logger.debug("Received db from #{inspect(node)}")
    wait_for_genserver(Karma.StoreAdapter)
    GenServer.cast(Karma.StoreAdapter, {:receive, data})
    state
  end

  def handle_info({:enslave, node}, state) do
    Logger.debug("#{inspect(node)} is enslaving himself")
    Node.monitor(node, true)

    state = if state[:main] == nil, do: Map.put(state, :main, Node.self()), else: state

    start_trigger()

    if Connector.cache_valid?() do
      send({Bot.Distri.Connector.CTask, node}, {:ack, Node.self(), :state})
    else
      send({Bot.Distri.Connector.CTask, node}, {:ack, Node.self()})
    end

    state
  end

  def handle_info({:set_data, data, node}, state) do
    if Connector.is_main(node) do
      Logger.debug("got data")
      Karma.StoreAdapter.set(data)
    end

    state
  end

  def handle_info({:set_out, id, room, user, karma, emoji}, state) do
    if Connector.is_main() do
      data = {id, room, user, karma, emoji}
      data = {:set_data, data, Node.self()}
      Logger.debug("sending data: #{inspect(data)}")
      send_out(data)
    end

    state
  end

  def handle_info({:update_since_int, since}, state) do
    # Logger.debug("updating since")
    send_out({:update_since, since})
    state |> Map.put(:since, since)
  end

  def handle_info({:update_since, since}, state) do
    state |> Map.put(:since, since)
  end

  def handle_info({:now_auth}, state) do
    if state[:main] == Node.self() && Connector.is_main() && Connector.could_save?() do
      Logger.info("we now think we are authoritiv")
      # push_data()
      Logger.debug("enable scraper with since #{inspect(state[:since])}")
      pid = wait_for_pid(Lib.Matrix.Scraper)
      send(pid, {:enable, state[:since]})
      Connector.set_valid(true)
    else
      Logger.debug(
        "Not Authorotiv: state: #{inspect(state[:main])}, main: #{inspect(Connector.is_main())}, could save: #{
          inspect(Connector.could_save?())
        }"
      )

      pid = wait_for_pid(Lib.Matrix.Scraper)
      send(pid, {:disable})
      Connector.set_valid(false)
    end

    state
  end

  # helper function
  def handle_info({:show_inner_state, pid}, state) do
    send(pid, {:inner_state, state})
    state
  end

  def get_inner_state() do
    send(Bot.Distri.Connector.CTask, {:show_inner_state, self()})

    receive do
      {:inner_state, state} -> state
    end
  end

  defp connect_first_main([node | tail]) do
    if node == Node.self() do
      Logger.debug("I am Main")
      {:ok, node}
    else
      if !Node.connect(node) do
        connect_first_main(tail)
      else
        Logger.debug("connected to first main #{inspect(node)}")
        {:ok, node}
      end
    end
  end

  defp connect_first_main([]) do
    {:error, :nomain}
  end

  defp wait_for_genserver(name) do
    if GenServer.whereis(name) != nil do
      true
    else
      :timer.sleep(100)
      wait_for_genserver(name)
    end
  end

  defp wait_for_pid(name) do
    pid = Process.whereis(name)

    if pid != nil do
      pid
    else
      :timer.sleep(100)
      wait_for_pid(name)
    end
  end

  defp send_out(data) do
    nodes = Connector.nodes() |> Enum.filter(&(&1 != Node.self()))

    send_out(nodes, data)
  end

  defp send_out([node | tail], data) do
    send({Bot.Distri.Connector.CTask, node}, data)
    send_out(tail, data)
  end

  defp send_out([], _), do: nil

  defp push_data() do
    Connector.nodes() |> Enum.filter(&(&1 != Node.self())) |> push_data()
  end

  defp push_data([node | tail]) do
    GenServer.cast(Karma.StoreAdapter, {:send, node})
    push_data(tail)
  end

  defp push_data([]), do: nil

  defp start_trigger do
    if node == Node.self() do
      pid = self()

      spawn_link(fn ->
        :timer.sleep(600)
        send(pid, {:now_auth})
      end)
    end
  end

  defp connect_after(node \\ Node.self()) do
    get_after(node)
    |> Enum.map(&connect(&1))
  end

  defp get_after(node \\ Node.self()) do
    nodes = Connector.nodes()
    connected = Node.list()

    nodes = Enum.with_index(nodes)

    {_, index} = hd(nodes |> Enum.filter(fn {n, i} -> n == node end))

    nodes
    |> Enum.filter(fn {n, i} -> i > index end)
    |> Enum.map(fn {n, i} -> n end)
    |> Enum.filter(&(!(connected |> Enum.member?(&1))))
  end

  defp connect(node) do
    if Node.connect(node) do
      Logger.debug("connected to sub node #{inspect(node)}")
      Node.monitor(node, true)
      send({Bot.Distri.Connector.CTask, node}, {:taking_main, Node.self()})
    end
  end

  # defp filter_connected()
end
