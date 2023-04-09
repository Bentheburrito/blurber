defmodule BlurberTest do
  use ExUnit.Case
  doctest Blurber

  test "greets the world" do
    assert Blurber.hello() == :world
  end
end
