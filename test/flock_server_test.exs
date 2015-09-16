defmodule FlockServerTest do
  use ExUnit.Case, async: true

  setup do
    Application.ensure_all_started(:flock)
    on_exit fn ->
      Flock.Server.stop_all
    end
    :ok
  end

  test "starting a node" do
    assert :test@localhost == Flock.Server.start_node(:test, %{})
    assert :pong = :net_adm.ping(:test@localhost)
    assert :x = Flock.Server.rpc(:test, String, :to_atom, ["x"])
    assert [:test@localhost] = Flock.Server.nodes
  end

  test "starting a node with apps" do
    assert :test@localhost == Flock.Server.start_node(:test, %{apps: [:sasl]})
    apps = Flock.Server.rpc(:test, :application, :which_applications, [])
    assert {:sasl, _, _} = :lists.keyfind(:sasl, 1, apps)
  end

  test "starting a node with config" do
    assert :test@localhost == Flock.Server.start_node(:test, %{config: ["config/test_config.exs"]})
    assert [foo: :bar] = Flock.Server.rpc(:test, :application, :get_all_env, [:dummy_app])
  end

  test "stopping a node" do
    Flock.Server.start_node(:test, %{})
    assert [:test@localhost] = Flock.Server.nodes
    assert :ok = Flock.Server.stop_node(:test)
    assert {:badrpc, :nodedown} = Flock.Server.rpc(:test, String, :to_atom, ["x"])
    assert [] = Flock.Server.nodes
  end

  test "stopping all nodes" do
    Flock.Server.start_node(:test1, %{})
    Flock.Server.start_node(:test2, %{})
    assert [:test1@localhost, :test2@localhost] == Flock.Server.nodes
    assert :ok = Flock.Server.stop_all
    assert {:badrpc, :nodedown} = Flock.Server.rpc(:test1, String, :to_atom, ["x"])
    assert [] = Flock.Server.nodes
  end

  test "nodes can see each other" do
    nodes = [:one, :two, :three, :four, :five]
    Flock.Server.start_nodes(nodes, %{})
    all = [node(), :one@localhost, :two@localhost, :three@localhost, :four@localhost, :five@localhost]
    Enum.each(nodes, fn(node) -> can_see(node, all) end )
  end

  test "partitioned servers" do
    Flock.Server.start_nodes([[:one, :two, :three], [:four, :five]], %{})
    assert :x = Flock.Server.rpc(:one, :rpc, :call, [:two@localhost,  String, :to_atom, ["x"]])
    assert {:badrpc, :nodedown} = Flock.Server.rpc(:one, :rpc, :call, [:four@localhost,  String, :to_atom, ["x"]])
    # make sure messages don't cause a reconnect
    assert :hello = Flock.Server.rpc(:one, :erlang, :send, [{:flock_server, :four@localhost}, :hello])
    goup1 = Enum.sort([node(), :one@localhost, :two@localhost, :three@localhost])
    can_see(:one,   goup1)
    can_see(:two,   goup1)
    can_see(:three, goup1)
    goup2 = Enum.sort([node(), :four@localhost, :five@localhost])
    can_see(:four, goup2)
    can_see(:five, goup2)
  end

  test "network split" do
    Flock.Server.start_nodes([:one, :two, :three, :four, :five], %{})
    Flock.Server.split([[:one, :two, :three], [:four, :five]])
    assert :x = Flock.Server.rpc(:one, :rpc, :call, [:two@localhost,  String, :to_atom, ["x"]])
    assert {:badrpc, :nodedown} = Flock.Server.rpc(:one, :rpc, :call, [:four@localhost,  String, :to_atom, ["x"]])
    # make sure messages don't cause a reconnect
    assert :hello = Flock.Server.rpc(:one, :erlang, :send, [{:flock_server, :four@localhost}, :hello])
    goup1 = Enum.sort([node(), :one@localhost, :two@localhost, :three@localhost])
    can_see(:one,   goup1)
    can_see(:two,   goup1)
    can_see(:three, goup1)
    goup2 = Enum.sort([node(), :four@localhost, :five@localhost])
    can_see(:four, goup2)
    can_see(:five, goup2)
  end

  test "join" do
    Flock.Server.start_nodes([:one, :two, :three], %{})
    Flock.Server.split([[:one, :two], [:three]])
    assert [:test_master@localhost, :two@localhost] == visible_nodes(:one)
    Flock.Server.join
    expected = Enum.sort([node(), :two@localhost, :three@localhost])
    assert expected == visible_nodes(:one)
  end

  test "changing groups" do
    Flock.Server.start_nodes([[:one, :two], [:three]], %{})
    can_see(:one,   [node(), :two@localhost])
    can_see(:two,   [node(), :one@localhost])
    can_see(:three, [node()])
    Flock.Server.split([[:one], [:two, :three]])
    can_see(:one,   [node()])
    can_see(:two,   [node(), :three@localhost])
    can_see(:three, [node(), :two@localhost])
    Flock.Server.join
    can_see(:one,   [node(), :two@localhost, :three@localhost])
    can_see(:two,   [node(), :one@localhost, :three@localhost])
    can_see(:three, [node(), :one@localhost, :two@localhost])
  end

  def visible_nodes(name) do
    Enum.sort(Flock.Server.rpc(name, :erlang, :nodes, []))
  end

  def can_see(name, others) do
    assert Enum.sort(others -- [Flock.Server.node_name(name)]) == Enum.sort(visible_nodes(name))
  end

end
