defmodule Repl.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {Task.Supervisor, name: Repl.TaskSupervisor},
      {Task.Supervisor, name: Repl.Spawner.TaskSupervisor},
      Repl.Spawner,
      {Repl, nil}
    ]

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end
end
