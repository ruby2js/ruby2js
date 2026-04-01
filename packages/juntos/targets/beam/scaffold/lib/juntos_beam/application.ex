defmodule JuntosBeam.Application do
  use Application

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT", "3000"))

    children = [
      # Start :pg for distributed broadcast subscriptions
      JuntosBeam.Cable,
      # Start the QuickBEAM runtime pool
      JuntosBeam,
      # Start the HTTP server
      {Bandit, plug: JuntosBeam.Router, port: port}
    ]

    opts = [strategy: :one_for_one, name: JuntosBeam.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
