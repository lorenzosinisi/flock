defmodule Flock.Server do
  use GenServer

  @server :flock_server

  def start_nodes(names, options) when is_list(names) and is_map(options) do
    Enum.map(names, fn(name) -> start_node(name, options) end)
  end

  def start_node(name, options) when is_atom(name) and is_map(options) do
    GenServer.call(@server, {:start_node, name, Map.get(options, :config, nil), Map.get(options, :apps, [])})
  end

  def stop_node(name) do
    GenServer.call(@server, {:stop_node, name})
  end

  def stop_all do
    GenServer.call(@server, {:stop_all})
  end

  def split(groups) do
    GenServer.call(@server, {:split, groups})
  end

  def join do
    GenServer.call(@server, {:join})
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

  def handle_call({:stop_all}, _from, state = %{nodes: nodes}) do
    Enum.each(
      nodes,
      fn(node_name) ->
        :ok = :slave.stop(node_name)
      end
    )
    {:reply, :ok, %{ state | nodes: [] }}
  end

  def handle_call({:split, groups}, _from, state) do
    Enum.each(groups, fn(group) -> enforce_group(group, List.flatten(groups) -- group ) end)
    {:reply, :ok, state}
  end

  def handle_call({:join}, _from, state = %{nodes: nodes}) do
    enforce_group(Enum.map(nodes, &node_id/1), [])
    {:reply, :ok, state}
  end

  def handle_call({:nodes}, _from, state = %{nodes: nodes}) do
    {:reply, nodes, state}
  end

  def enforce_group(members, others) do
    Enum.each(
      members,
      fn(member) ->
        connect_to_all(member, members)
        disconnect_from_all(member, others)
      end
    )
  end

  def connect_to_all(member, other_members) do
    Enum.each(
    other_members,
    fn(other_member) ->
      case rpc(member, :net_adm, :ping, [node_name(other_member)]) do
        :pong -> :ok
        other -> throw({:error, {:unexpected, member, other}})
      end
    end
  )
  end

  def disconnect_from_all(member, others) do
    Enum.each(
      others,
      fn(other) ->
        case rpc(member, :erlang, :disconnect_node, [node_name(other)]) do
          true -> :ok
          false-> :ok
          other -> throw({:error, {:unexpected, member, other}})
        end
      end
    )
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

  def node_id(node_name) do
    [_, id] = Regex.run(~r/([^@]*)@/, Atom.to_string(node_name))
    String.to_atom(id)
  end

end
