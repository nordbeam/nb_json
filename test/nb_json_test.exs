defmodule NbJsonTest do
  use ExUnit.Case
  doctest NbJson

  test "exposes the package version" do
    assert NbJson.version() == "0.1.0"
  end
end
