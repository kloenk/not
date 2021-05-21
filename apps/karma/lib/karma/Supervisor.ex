defmodule Karma.Supervisor do
  use Supervisor

  @impl true
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      {Karma.MemoryStore, nil},
      {Karma.StoreAdapter, Karma.MemoryStore},
      {Karma, nil}
    ]

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end
end
