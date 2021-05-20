alias MatrixSDK.Client
alias Lib.Matrix.Scraper

defmodule Lib.Matrix.Server do
  use GenServer
  require Logger

  def start_link(pids \\ []) do
    GenServer.start_link(__MODULE__, pids, name: __MODULE__)
  end

  @spec init(map() | list(pid())) :: {:ok, map()}
  @impl true
  def init(data \\ [])

  def init(config) when is_map(config) or is_list(config) do
    config = read_config(config)
    server = config[:server]

    {config, login} = get_login(config)
    token = Scraper.login(login, server)

    config =
      config
      |> Map.put(:token, token)

    {:ok, config}
  end

  @spec subscribe(pid()) :: pid()
  def subscribe(pid \\ self()) do
    GenServer.cast(__MODULE__, {:add_pid, pid})
    pid
  end

  def unsubscribe(pid \\ self()) do
    GenServer.call(__MODULE__, {:remove_pid, pid})
  end

  def get_subscribers do
    GenServer.call(__MODULE__, {:get_subscribers})
  end

  def get_pid do
    GenServer.call(__MODULE__, {:get_pid})
  end

  def get_server do
    GenServer.call(__MODULE__, {:get_server})
  end

  def get_token do
    GenServer.call(__MODULE__, {:get_token})
  end

  # MARK: - Implementation
  @impl true
  def handle_call({:remove_pid, pid}, _from, state) do
    new_pids =
      state[:pids]
      |> Enum.filter(&(&1 != pid))

    state = Map.put(state, :pids, new_pids)

    {:reply, pid, state}
  end

  @impl true
  def handle_call({:get_pid}, _from, state) do
    {:reply, self(), state}
  end

  @impl true
  def handle_call({:get_subscribers}, _from, state) do
    {:reply, state[:pids], state}
  end

  @impl true
  def handle_call({:get_server}, _from, state) do
    {:reply, state[:server], state}
  end

  @impl true
  def handle_call({:get_token}, _from, state) do
    {:reply, state[:token], state}
  end

  @impl true
  def handle_cast({:add_pid, pid}, state) do
    new_pids = [pid | state[:pids]]

    state = Map.put(state, :pids, new_pids)

    {:noreply, state}
  end

  @impl true
  def handle_info({:sync, tesla}, state) do
    # Logger.debug("got sync")
    send_sync(state[:pids], tesla)

    {:noreply, state}
  end

  # MARK: - Private functions
  @spec send_sync(list(pid()), Tesla.Env) :: nil
  defp send_sync([head | tail], sync) do
    send(head, {:send_sync, sync})

    send_sync(tail, sync)
  end

  defp send_sync([], _sync) do
    nil
  end

  defp read_config(pids) when is_list(pids) do
    read_config(%{pids: pids})
  end

  defp read_config(config) when is_map(config) do
    env = Application.fetch_env!(:bot, :login)

    cfg = %{}

    cfg =
      if config[:server] != nil do
        Map.put(cfg, :server, config[:server])
      else
        Map.put(cfg, :server, env[:server])
      end

    cfg =
      if config[:token] != nil do
        Map.put(cfg, :token, config[:token])
      else
        Map.put(cfg, :token, env[:token])
      end

    cfg =
      if config[:rooms] != nil do
        Map.put(cfg, :rooms, config[:rooms])
      else
        Map.put(cfg, :rooms, env[:rooms])
      end

    cfg =
      if config[:admins] != nil do
        Map.put(cfg, :admins, config[:admins])
      else
        Map.put(cfg, :admins, env[:admins])
      end

    cfg =
      if config[:type] != nil do
        Map.put(cfg, :type, config[:type])
      else
        Map.put(cfg, :type, env[:type])
      end

    cfg =
      if cfg[:type] == :password do
        cfg =
          if config[:password] != nil do
            Map.put(cfg, :password, config[:password])
          else
            Map.put(cfg, :password, env[:password])
          end

        cfg =
          if config[:username] != nil do
            Map.put(cfg, :username, config[:username])
          else
            Map.put(cfg, :username, env[:username])
          end

        cfg
      else
        throw("unnsuported login type")
      end

    cfg = if config[:pids] != nil, do: Map.put(cfg, :pids, config[:pids]), else: cfg

    cfg
  end

  defp get_login(config) when is_map(config) do
    if config[:type] == :password do
      login = Client.Auth.login_user(config[:username], config[:password])

      {_, config} = Map.pop(config, :username)
      {_, config} = Map.pop(config, :password)

      {config, login}
    else
      throw("unnsuported login type")
    end
  end
end
