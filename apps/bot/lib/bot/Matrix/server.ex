alias MatrixSDK.Client
alias MatrixSDK.Client.Request

defmodule Bot.Matrix.Server do
  use GenServer
  require Logger

  @default_server "https://matrix.org"
  @errcode "errcode"
  @error "error"

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil)
  end

  @spec init(map() | nil):: {:ok, %{admins: nil | list(binary()), rooms: nil | list(binary), token: binary()}}
  @impl true
  def init(data \\ nil)

  def init(data) when data != nil do
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
      admins: data[:admins]
    }}
  end

  def init(_data) do
    config = Application.fetch_env!(:bot, :login)

    login = case config[:type] do
      :password -> Client.Auth.login_user(config[:username], config[:password])
      _ -> throw("unnsuported login type")
    end

    init(%{
      server: config[:server],
      login: login,
      rooms: config[:rooms],
      admins: config[:admins]
    })
  end

  # MARK: - Implementation
  @impl true
  def handle_info({:sync, tesla}, state) do
    Logger.debug("got sync")
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
end
