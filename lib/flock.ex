defmodule Flock do
  use Application

  def start(_type, _args) do
    Flock.Supervisor.start_link
  end

end
