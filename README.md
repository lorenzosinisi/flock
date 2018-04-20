flock
=====

flock is an elixir application to simulate and test distributed erlang/elixir applications.
It can start nodes (erlang VMs), configure them and let them start applications.
In addition it can simulate failure scenarios like nodes going down, network splits and network re-joins.
flock is based on the ["slave" module in Erlang](http://erlang.org/doc/man/slave.html).

# Usage
To use flock in the tests of your mix project add it as an dependency and run your tests with `./deps/flock/run_test`. This is needed since we need a special node setup.

## Example

* start two nodes in separate clusters with Mix running
* try to ping one from the other and fail
* join the nodes
* ping again and succeed

`iex --hidden --sname flock@localhost -S mix`

```elixir
Application.ensure_all_started(:flock)
---> {:ok, []}
Flock.Server.start_nodes([[:one], [:two]], %{rpcs: Flock.Server.mix_rpcs})
---> [:one@localhost, :two@localhost]
Flock.Server.rpc(:one, :net_adm, :ping, [:"two@localhost"])
---> :pang
=ERROR REPORT==== 20-Apr-2018::17:49:42 ===
** Connection attempt from disallowed node one@localhost **
Flock.Server.group([[:one, :two]])
---> :ok
Flock.Server.rpc(:one, :net_adm, :ping, [:"two@localhost"])
---> :pong
```

For the full range of features useful in tests see `test/floc_server_test.ex`.


# Tests
`mix compile && ./run_test`
