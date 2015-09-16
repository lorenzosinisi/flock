flock
=====

flock is and elixir application to simulate and test distributed erlang/elixir applications.
It can start nodes (erlang VMs) configure them and let them start applications.
In addition it can simulate failure scenarios like nodes going down, network splits and network re-joins.

# usage
see `test/floc_server_test.ex` for now.

# tests
`mix compile && ./run_test`
