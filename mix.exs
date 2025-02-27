defmodule OpentelemetryPlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :opentelemetry_plug,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.xml": :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test
      ],
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry, "~> 1.5"},
      {:plug, "~> 1.16"},
      {:telemetry, "~> 1.3"},
      # Test dependencies
      {:mock, "~> 0.3", only: :test},
      {:excoveralls, "~> 0.18", [only: [:dev, :test]]},
      {:hackney, "~> 1.2", only: :test, runtime: false},
      # {:opentelemetry, "~> 1.5", only: :test},
      {:plug_cowboy, "~> 2.7", only: :test, runtime: false},
      {:ssl_verify_fun, "~> 1.1.7", only: :test},
      {:credo, "~> 1.7", [only: [:dev, :test], runtime: false]},
      {:dialyxir, "~> 1.4", [only: [:dev, :test], runtime: false]}
    ]
  end
end
