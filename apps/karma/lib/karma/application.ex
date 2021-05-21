defmodule Karma.Application do
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end

  @impl true
  def start_link() do
    children = [
      {Karma.MemoryStore, nil},
      {Karma.StoreAdapter, Karma.MemoryStore},
      {Karma, nil}
    ]

    opts = [strategy: :one_for_one, name: Karma.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
