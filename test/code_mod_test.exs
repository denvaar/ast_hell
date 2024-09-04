defmodule CodeModTest do
  use ExUnit.Case
  doctest CodeMod

  test "greets the world" do
    assert CodeMod.hello() == :world
  end
end
