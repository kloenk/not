defmodule Bot.Distri.Supervisor do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      {Bot.Distri.Connector, nil},
      {Bot.Distri.Connector.CTask, nil}
    ]

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end
end
