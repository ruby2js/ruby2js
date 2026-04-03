defmodule JuntosBeam.MixProject do
  use Mix.Project

  def project do
    [
      app: :juntos_beam,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {JuntosBeam.Application, []}
    ]
  end

  defp deps do
    [
      {:quickbeam, "~> 0.8"},
      {:bandit, "~> 1.0"},
      {:websock_adapter, "~> 0.5"},
      {:postgrex, "~> 0.19", optional: true},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},
      {:req, "~> 0.5"}
    ]
  end
end
