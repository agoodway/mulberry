defmodule MulberryTest do
  use ExUnit.Case
  doctest Mulberry

  test "greets the world" do
    assert Mulberry.hello() == :world
  end
end
