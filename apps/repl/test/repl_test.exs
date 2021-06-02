defmodule ReplTest do
  use ExUnit.Case
  doctest Repl

  test "greets the world" do
    assert Repl.hello() == :world
  end
end
