defmodule LibTest do
  use ExUnit.Case
  doctest Lib

  test "greets the world" do
    assert Lib.hello() == :world
  end
end
