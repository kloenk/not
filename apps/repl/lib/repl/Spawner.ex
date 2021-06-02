alias Repl.Executor

defmodule Repl.Spawner do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    state = read_servers()

    state =
      state
      |> Map.put(:vars, %{
        "_show" => "x: x",
        "pkgs" => "import <nixpkgs> {}",
        "lib" => "pkgs.lib"
      })
      |> Map.put(:protected, ["_show", "pkgs", "lib"])

    env = Application.fetch_env(:repl, :args)

    state =
      if env != :error do
        Map.put(state, :args, env[:nix])
      else
        Map.put(state, :args, [
          "--strict",
          "--sandbox",
          "--restrict-eval",
          "--fsync-metadata",
          "--no-allow-import-from-derivation"
          # "--show-trace"
        ])
      end

    {:ok, state}
  end

  def get_vars() do
    GenServer.call(__MODULE__, {:vars})
  end

  def generate_expr(:err) do
    :err
  end

  def generate_expr(expr) do
    GenServer.call(__MODULE__, {:expr, expr})
  end

  def add_var(name, value, force \\ false) when is_binary(force) do
    GenServer.cast(__MODULE__, {:add_var, {name, value}, force})
  end

  def compute(content, room, system, event) do
    GenServer.cast(__MODULE__, {:compute, content, room, system, event})
  end

  # MARK: - Handlers
  @impl true
  def handle_call({:vars}, _from, state) do
    {:reply, state[:vars], state}
  end

  @impl true
  def handle_call({:expr, expr}, _from, state) do
    {:reply, gen_expr(expr, state), state}
  end

  @impl true
  def handle_call({:add_var, {name, value}, force}, _from, state) do
    {reply, state} =
      if force do
        put_in(state[:vars][name], value)
      else
        add_var_inner(state, name, value)
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:compute, content, room, system, event}, state) do
    {expr, state} = compute_inner(content, state)

    expr = gen_expr(expr, state)

    args = state[:args] |> Enum.join(" ")

    # Task.Supervisor.async_nolink(Repl.Spawner.TaskSupervisor, fn -> run(expr, args, room) end)
    spawn(fn -> Executor.run(expr, args, room, system, event) end)

    # Task.Supervisor.start_child(Repl.Spawner.TaskSupervisor, fn -> Executor.run(expr, args, room) end)

    {:noreply, state}
  end

  @impl true
  def handle_info({_ref, :ok}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  # MARK: - Private
  defp gen_let(vars) when is_map(vars) do
    vars
    |> Enum.to_list()
    |> Enum.map(fn {n, v} -> n <> " = " <> v <> ";" end)
    |> Enum.join("\n")
  end

  defp read_servers() do
    case Application.fetch_env(:repl, :servers) do
      {:ok, env} -> env
      _ -> %{}
    end
    |> read_servers
  end

  defp read_servers(env) do
    arch = own_arch()
    list = Map.get(env, arch, [])
    list = if !Enum.member?(list, Node.self()), do: [Node.self() | list], else: list

    Map.put(env, arch, list)
  end

  defp add_var_inner(state, name, value) do
    protected = state[:protected]

    if Enum.member?(protected, name) do
      {:protected, state}
    else
      state = put_in(state[:vars][name], value)
      {:ok, state}
    end
  end

  def own_arch do
    case :os.type() do
      {:unix, :darwin} -> own_arch(:darwin)
      {:unix, :linux} -> own_arch(:linux)
    end
  end

  defp own_arch(:darwin) do
    [arch | _] =
      :erlang.system_info(:system_architecture)
      |> :binary.list_to_bin()
      |> String.split("-", parts: 2)

    arch <> "-darwin"
  end

  defp own_arch(:linux) do
    [arch | _] =
      :erlang.system_info(:system_architecture)
      |> :binary.list_to_bin()
      |> String.split("-", parts: 2)

    arch <> "-linux"
  end

  defp compute_inner([{which, what} | tail], state) do
    if which == :code do
      {what, state}
    else
      {name, value} = what
      # FIXME
      {_, state} = add_var_inner(state, name, value)
      compute_inner(tail, state)
    end
  end

  defp compute_inner([], state), do: {:err, state}

  defp gen_expr(:err, state) do
    :err
  end

  defp gen_expr(expr, state) do
    "let\n" <> gen_let(state[:vars]) <> "\nin\n" <> expr
  end
end
