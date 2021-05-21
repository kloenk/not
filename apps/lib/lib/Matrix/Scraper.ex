alias MatrixSDK.Client
alias MatrixSDK.Client.Request
alias Lib.Matrix.Server

defmodule Lib.Matrix.Scraper do
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
    pid = if pid != nil, do: pid, else: pid = Server.get_server_pid()

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

  def get_room_id(room, token, server \\ nil) when token != nil do
    response =
      server
      |> default_server()
      |> Request.join_room(token, room)
      |> Client.do_request()

    case response do
      {:ok, response} ->
        if error?(response), do: {:ok, room}, else: {:ok, response.body["room_id"]}

      _ ->
        response
    end
  end

  def get_room_event(room, id, token \\ Server.get_token(), server \\ Server.get_server())
      when is_binary(room) and is_binary(id) do
    response =
      server
      |> default_server()
      |> Request.room_event(token, room, id)
      |> Client.do_request()

    case response do
      {:ok, response} ->
        if error?(response), do: {:error, response.body}, else: {:ok, response.body}

      _ ->
        response
    end
  end

  def get_profile(id, server \\ Server.get_server()) when is_binary(id) do
    response =
      server
      |> default_server()
      |> Request.user_profile(id)
      |> Client.do_request()

    case response do
      {:ok, response} ->
        if error?(response), do: {:error, response.body}, else: {:ok, response.body}

      _ ->
        response
    end
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
  # Returns true if tesla.body contains an @errcode
  defp error?(tesla) do
    case tesla.body[@errcode] do
      nil -> false
      _ -> true
    end
  end

  defp sync(pid, token, server, since \\ nil) do
    params = if since == nil, do: %{}, else: %{since: since, timeout: 1000}

    # {:ok, response} =
    #  server
    #  |> Request.sync(token, params)
    #  |> Client.do_request()

    response =
      server
      |> Request.sync(token, params)
      |> Client.do_request()

    response =
      case response do
        {:ok, data} ->
          data

        {:error, e} ->
          Logger.warn("error syncing: #{inspect(e)}")
          nil
      end

    since =
      if response != nil do
        send(pid, {:sync, response})
        response.body["next_batch"]
      else
        since
      end

    sync(pid, token, server, since)
  end
end
