alias MatrixSDK.Client
alias MatrixSDK.Client.Request

defmodule Bot.Matrix.Server do
  use GenServer
  require Logger

  @default_server "https://matrix.org"
  @errcode "errcode"
  @error "error"

  def start_link(pids \\ []) do
    GenServer.start_link(__MODULE__, pids)
  end

  @spec init(map() | list(pid())):: {:ok, %{admins: nil | list(binary()), rooms: nil | list(binary()), token: binary(), pids: list(pid())}}
  @impl true
  def init(data \\ [])

  def init(data) when is_map(data) do
    server = data[:server]
    server = if server == nil, do: @default_server, else: server

    login = data[:login]

    if login == nil, do: throw "no login data provided"

    {:ok, response } = server
      |> Request.login(login)
      |> Client.do_request()

    token = response.body["access_token"]
    IO.inspect(response)

    if error?(response) == true, do: throw "error logging in #{response.body[@errcode]} (#{response.body[@error]})"

    pid = self()
    spawn(fn -> sync(pid, token, server) end)

    {:ok, %{
      token: token,
      rooms: data[:rooms],
      admins: data[:admins],
      pids: data[:pids]
    }}
  end

  def init(data) when is_list(data) do
    config = Application.fetch_env!(:bot, :login)

    login = case config[:type] do
      :password -> Client.Auth.login_user(config[:username], config[:password])
      _ -> throw("unnsuported login type")
    end

    init(%{
      server: config[:server],
      login: login,
      rooms: config[:rooms],
      admins: config[:admins],
      pids: data
    })
  end

  @spec subscribe(pid()) :: pid()
  def subscribe(pid) do
    GenServer.cast(__MODULE__, {:add_pid, pid})
    pid
  end

  def unsubscribe(pid) do
    GenServer.call(__MODULE__, {:remove_pid, pid})
  end

  # MARK: - Implementation
  @impl true
  def handle_call({:remove_pid, pid}, _from, state) do
    new_pids = state[:pids]
      |> Enum.filter( &(&1 != pid) )

    state = Map.put(state, :pids, new_pids)

    {:reply, pid, state}
  end

  @impl true
  def handle_cast({:add_pid, pid}, state) do
    new_pids = [ pid | state[:pids] ]

    state = Map.put(state, :pids, new_pids)

    {:noreply, state}
  end

  @impl true
  def handle_info({:sync, tesla}, state) do
    Logger.debug("got sync")
    send_sync(state[:pids], tesla)
    IO.inspect(tesla.body["rooms"])

    {:noreply, state}
  end

  # MARK: - Private functions

  # Returns true if tesla.body contains an @errcode
  defp error?(tesla) do
    case tesla.body[@errcode] do
      nil -> false
      _ -> true
    end
  end

  defp sync(pid, token, server, since \\ nil) do
    params = if since == nil, do: %{}, else: %{since: since, timeout: 1000}

    {:ok, response} = server
      |> Request.sync(token, params)
      |> Client.do_request()

    send(pid, {:sync, response})

    sync(pid, token, server, response.body["next_batch"])
  end


  @spec send_sync(list(pid()), Tesla.Env):: nil
  defp send_sync([head | tail], sync) do
    send(head, {:send_sync, sync})

    send_sync(tail, sync)
  end

  defp send_sync([], _sync) do
    nil
  end
end
