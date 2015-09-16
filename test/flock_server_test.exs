defmodule FlockServerTest do
  use ExUnit.Case

  setup do
    Application.ensure_all_started(:flock)
    on_exit fn ->
      Application.stop(:flock)
    end
    :ok
  end

  test "starting a node" do
    assert :test@localhost = Flock.Server.start_node(:test, %{})
    assert :pong = :net_adm.ping(:test@localhost)
    assert :x = Flock.Server.rpc(:test, String, :to_atom, ["x"])
    assert [:test@localhost] = Flock.Server.nodes
  end

  test "stopping a node" do
    Flock.Server.start_node(:test, %{})
    assert [:test@localhost] = Flock.Server.nodes
    assert :ok = Flock.Server.stop_node(:test)
    assert {:badrpc, :nodedown} = Flock.Server.rpc(:test, String, :to_atom, ["x"])
    assert [] = Flock.Server.nodes
  end

end
