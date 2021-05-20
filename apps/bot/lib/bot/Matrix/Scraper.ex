alias MatrixSDK.Client
alias MatrixSDK.Client.Request
alias Bot.Matrix.Server

defmodule Bot.Matrix.Scraper do
  use Task, restart: :permanent, id: __MODULE__
  require Logger

  @default_server "https://matrix.org"
  @errcode "errcode"
  @error "error"

  def start_link(arg \\ nil) do
    {:ok, pid} = Task.start_link(__MODULE__, :run, [arg])
    Process.register(pid, __MODULE__)
    {:ok, pid}
  end

  def run(pid \\ nil) when pid == nil or is_pid(pid) do
    pid = if pid != nil, do: pid, else: pid = get_server_pid()

    sync(pid, Server.get_token(), Server.get_server())
  end

  # MARK: - Helpers
  def login(login, server \\ nil) when login != nil do
    {:ok, response} =
      default_server(server)
      |> Request.login(login)
      |> Client.do_request()

    if error?(response) == true,
      do: throw("error logging in #{response.body[@errcode]} (#{response.body[@error]})")

    response.body["access_token"]
  end

  @spec default_server(nil | binary()) :: binary()
  def default_server(server \\ nil)

  def default_server(server) when server == nil do
    @default_server
  end

  def default_server(server) when is_binary(server) do
    server
  end

  # MARK: - Private functions
  defp get_server_pid() do
    pid = GenServer.whereis(Bot.Matrix.Server)

    if pid == nil do
      Logger.debug("sleeping 500ms")
      :timer.sleep(500)
      get_server_pid()
    else
      Logger.debug("found pid")
      pid
    end
  end

  # Returns true if tesla.body contains an @errcode
  defp error?(tesla) do
    case tesla.body[@errcode] do
      nil -> false
      _ -> true
    end
  end

  defp sync(pid, token, server, since \\ nil) do
    params = if since == nil, do: %{}, else: %{since: since, timeout: 1000}

    {:ok, response} =
      server
      |> Request.sync(token, params)
      |> Client.do_request()

    send(pid, {:sync, response})

    # Remove.important!!!
    :timer.sleep(1000)

    sync(pid, token, server, response.body["next_batch"])
  end
end
