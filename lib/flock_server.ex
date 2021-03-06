defmodule Flock.Server do
  use GenServer

  @server :flock_server

  def start_node(name, options) when is_atom(name) and is_map(options) do
    [new_node] = start_nodes([name], options)
    new_node
  end

  def start_nodes(names = [first_name|_], options) when is_map(options) and is_atom(first_name) do
    start_nodes([names], options)
  end

  def start_nodes(groups = [first_group|_], options) when is_map(options) and is_list(first_group) do
    GenServer.call(@server, {:start_nodes, groups, Map.get(options, :rpcs, [])}, Map.get(options, :timeout, 10000))
  end

  def stop_node(name) do
    GenServer.call(@server, {:stop_node, name})
  end

  def stop_all do
    GenServer.call(@server, {:stop_all})
  end

  def group(groups) do
    GenServer.call(@server, {:group, groups})
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

  def rpc(name, fun) do
    :rpc.call(node_name(name), :erlang, :apply, [fun, []])
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: @server)
  end

  def mix_rpcs do
    [
      {Application,          :ensure_all_started, [:mix]},
      {Mix.Tasks.Loadconfig, :run,                [[]]},
      {Code,                 :load_file,          ["mix.exs"]}
    ]
 end

 def load_config_rpcs(FileName) do
   [{__MODULE__, :apply_config, [FileName]}]
 end

  def init([]) do
    state = %{
      nodes: []
    }
    {:ok, state}
  end

  def handle_call({:start_nodes, groups = [first_group|_], rpcs}, _from, state = %{nodes: nodes}) when is_list(first_group) do
    new_nodes = Enum.map(List.flatten(groups), &start_node/1)
    enforce_groups(groups)
    Enum.each(new_nodes, fn(new_node) -> prepare_node(new_node, rpcs) end)
    {:reply, new_nodes, %{ state | nodes: nodes ++ new_nodes}}
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

  def handle_call({:group, groups}, _from, state) do
    enforce_groups(groups)
    {:reply, :ok, state}
  end

  def handle_call({:join}, _from, state = %{nodes: nodes}) do
    enforce_group(Enum.map(nodes, &node_id/1), 0, [])
    {:reply, :ok, state}
  end

  def handle_call({:nodes}, _from, state = %{nodes: nodes}) do
    {:reply, nodes, state}
  end

  def enforce_groups(groups) do
    Enum.each(
      Enum.with_index(groups),
      fn({group, index}) ->
        enforce_group(group, index, List.flatten(groups) -- group)
      end
    )
  end

  def enforce_group(members, index, others) do
    Enum.each(members, fn(member) -> set_cookie(member, index) end)
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

  def set_cookie(member, index) do
    rpc(member, :erlang, :set_cookie, [node_name(member), String.to_atom("group_cookie_" <> inspect(index)) ])
  end

  def start_node(name) do
    # start the node
    {:ok, node} = :slave.start_link(:localhost, name)
    # add all the paths
    Enum.each(
      :code.get_path,
      fn(path) -> true = :rpc.call(node, :code, :add_path, [path]) end
    )
    node
  end

  def prepare_node(node, rpcs) do
    Enum.each(
      rpcs,
      fn({module, function, args}) ->
        case :rpc.call(node, module, function, args) do
          {:badrpc, reason} ->
            throw({:badrpc, {reason, {node, module, function, args}}})
          _ ->
            :noop
        end
      end
    )
    node
  end

  def node_name(name) when is_atom(name) do
    String.to_atom(Atom.to_string(name) <> "@localhost")
  end

  def node_id(node_name) do
    [_, id] = Regex.run(~r/([^@]*)@/, Atom.to_string(node_name))
    String.to_atom(id)
  end

  def apply_config(file_name) do
    {:ok, [configs]} = :file.consult(file_name)
    Enum.each(configs, fn({app, vars}) -> apply_app_config(app, vars) end)
  end

  def apply_app_config(app, vars) do
    Enum.each(vars, fn({key, value}) -> :application.set_env(app, key, value) end)
  end


end
