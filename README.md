flock
=====

flock is an elixir application to simulate and test distributed erlang/elixir applications.
It can start nodes (erlang VMs), configure them and let them start applications.
In addition it can simulate failure scenarios like nodes going down, network splits and network re-joins.

# usage
To use flock in the tests of your mix project add it as an dependency and run your tests with `./deps/flock/run_test`.
For details see `test/floc_server_test.ex` for now.


# tests
`mix compile && ./run_test`
