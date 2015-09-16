defmodule Flock.Server do
  use GenServer

  @server :flock_server

  def start_node(name, options) when is_atom(name) and is_map(options) do
    GenServer.call(@server, {:start_node, name, Map.get(options, :config, nil), Map.get(options, :apps, [])})
  end

  def stop_node (name) do
    GenServer.call(@server, {:stop_node, name})
  end

  def nodes do
    GenServer.call(@server, {:nodes})
  end

  def rpc(name, module, function, args) do
    :rpc.call(node_name(name), module, function, args)
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: @server)
  end

  def init([]) do
    state = %{
      nodes: []
    }
    {:ok, state}
  end

  def handle_call({:start_node, name, config, apps}, _from, state = %{nodes: nodes}) do
    node = start_node(name, config, apps)
    {:reply, node, %{ state | nodes: [node | nodes] }}
  end

  def handle_call({:stop_node, name}, _from, state = %{nodes: nodes}) do
    node_name = node_name(name)
    :ok = :slave.stop(node_name)
    {:reply, :ok, %{ state | nodes: nodes -- [node_name] }}
  end

  def handle_call({:nodes}, _from, state = %{nodes: nodes}) do
    {:reply, nodes, state}
  end

  def start_node(name, config, apps) do
    # start the node
    {:ok, node} = :slave.start_link(:localhost, name)
    # add all the paths
    Enum.each(
      :code.get_path,
      fn(path) -> true = :rpc.call(node, :code, :add_path, [path]) end
    )
    # elixir and mix
    {:ok, _} = :rpc.call(node, :application, :ensure_all_started, [:elixir])
    :rpc.call(node, Code, :require_file, ["mix.exs"])
    load_config(node, config)
    Enum.each(apps, fn(app) -> start_app(node, app) end)
    node
  end

  def start_app(node, app) do
    {:ok, _} = :rpc.call(node, :application, :ensure_all_started, [app])
  end

  def load_config(_node, nil) do
    :noop
  end

  def load_config(node, config) do
    configs = :rpc.call(node, Mix.Config, :read!, [config])
    Enum.each(
      configs,
      fn({app, config}) ->
        Enum.each(
          config,
          fn({key, value}) ->
            :ok = :rpc.call(node, :application, :set_env, [app, key, value])
          end
        )
      end
    )
  end

  def node_name(name) when is_atom(name) do
    String.to_atom(Atom.to_string(name) <> "@localhost")
  end

end