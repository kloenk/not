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

    config = resolve_rooms(config)

    {:ok, config}
  end

  def get_server_pid() do
    pid = GenServer.whereis(__MODULE__)

    if pid == nil do
      Logger.debug("sleeping 500ms")
      :timer.sleep(500)
      get_server_pid()
    else
      pid
    end
  end

  def wait_for_server do
    get_server_pid()
    true
  end

  def self_credit(name, id, room_id) do
    send_reply(
      room_id,
      "#{name} is selfish",
      "<a href=\"https://matrix.to/#/#{id}\">#{name}</a> is selfish"
    )
  end

  def send_karma(karma, name, id, room_id) when is_binary(name) and is_binary(id) do
    Logger.debug("giving karma to #{name}")

    send_reply(
      room_id,
      "#{name} has #{karma} points",
      "<a href=\"https://matrix.to/#/#{id}\">#{name}</a> has #{karma} points"
    )
  end

  def resolve_name(name) do
    profile = Scraper.get_profile(name, get_server)

    case profile do
      {:ok, profile} -> {:ok, profile["displayname"]}
      _ -> profile
    end
  end

  # Mark: - GenServer Calls

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

  def get_rooms do
    GenServer.call(__MODULE__, {:get_rooms})
  end

  def send_reply(room, message, html) do
    GenServer.cast(__MODULE__, {:reply, room, message, html})
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
  def handle_call({:get_rooms}, _from, state) do
    {:reply, state[:rooms], state}
  end

  @impl true
  def handle_cast({:add_pid, pid}, state) do
    new_pids = [pid | state[:pids]]

    state = Map.put(state, :pids, new_pids)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:reply, room, message, html}, state) do
    event = Client.RoomEvent.message(room, :text, message, UUID.uuid1())

    content = %{
      "body" => message,
      "format" => "org.matrix.custom.html",
      "formatted_body" => html,
      "msgtype" => "m.notice"
    }

    # event.content = content
    event = Map.put(event, :content, content)

    Client.Request.send_room_event(state[:server], state[:token], event)
    |> Client.do_request()

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

  defp resolve_rooms(config) when is_map(config) do
    rooms = config[:rooms]

    config = Map.put(config, :rooms, %{})
    resolve_rooms(rooms, config)
  end

  defp resolve_rooms([room | tail], config) when is_binary(room) and is_map(config) do
    id = Scraper.get_room_id(room, config[:token], config[:server])

    rooms = config[:rooms]

    rooms =
      case id do
        {:ok, id} ->
          Logger.debug("resolved room #{room} to #{id}")
          Map.put(rooms, id, room)

        {:error, err} when is_map(err) ->
          Logger.error("error resolving room: #{err["errcode"]} (#{err["error"]})")
          rooms

        {:error, err} ->
          Logger.error("error resolving room: #{inspect(err)}")
          rooms
      end

    config = Map.put(config, :rooms, rooms)
    resolve_rooms(tail, config)
  end

  defp resolve_rooms([], config), do: config
  defp resolve_rooms(room, config) when room == nil, do: config

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
