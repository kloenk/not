defmodule KarmaTest do
  use ExUnit.Case
  doctest Karma

  test "greets the world" do
    assert Karma.hello() == :world
  end
end
