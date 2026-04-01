defmodule JuntosBeam.Application do
  use Application

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT", "4000"))

    children = [
      # Start the JS runtime with the Juntos app
      {JuntosBeam, port: port},
      # Start the HTTP server
      {Bandit, plug: JuntosBeam.Router, port: port}
    ]

    opts = [strategy: :one_for_one, name: JuntosBeam.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
