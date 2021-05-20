alias MatrixSDK.Client.Request
alias MatrixSDK.Client

defmodule Bot do
  @default_server "https://matrix.petabyte.dev"

  require Logger

  def test(server \\ @default_server) do
    Logger.info("Running guest login example...")
    Logger.info("Registering guest user...")

    auth = Client.Auth.login_user("kloenk_masui_test", "zafBup-xisxuz-nipxu8")

    {:ok, response} =
      server
      |> Request.login(auth)
      |> Client.do_request()

    Logger.debug("Response: ")
    IO.inspect(response.body)

    token = response.body["access_token"]
    room = "#thisisatestroom:petabyte.dev"
    #room = "#thisisntatestroom:petabyte.dev"
    #room = "#elixirsdktest:matrix.org"

    Logger.info("Joining the #{room} room...")
    #{:ok, room_id} =

    {:ok, response } = join_room(room, token, server)
    room_id = response.body["room_id"]

    {:ok, response} =
      server
      |> Request.room_messages(token, room, "", "f")
      |> Client.do_request()

    Logger.debug("messages:")
    IO.inspect(response)

    Logger.info("Staring sync for room: #{inspect(room)}...")
    IO.puts("(press ctrl-c to stop")

    sync_loop(room_id, token, server)
  end

  defp join_room(room, token, server) do
    {:ok, response} =
      server
      |> Request.join_room(token, room)
      |> Client.do_request()


    case response.body["errcode"] do
      nil ->
        {:ok, response}
      _ -> {:error, response.body}
    end
  end

  defp sync_loop(room_id, token, server, since \\ nil) do
    params = if since == nil, do: %{}, else: %{since: since, timeout: 1000}

    {:ok, response} =
      server
      |> Request.sync(token, params)
      |> Client.do_request

    IO.inspect(response.body["rooms"]["join"][room_id])

    sync_loop(room_id, token, server, response.body["next_batch"])
  end
  @moduledoc """
  Documentation for `Bot`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Bot.hello()
      :world

  """
  def hello do
    :world
  end
end
