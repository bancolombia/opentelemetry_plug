defmodule OpentelemetryPlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :opentelemetry_plug,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:plug, "~> 1.16"},
      {:telemetry, "~> 1.3"},
      # Test dependencies
      {:hackney, "~> 1.2", only: :test, runtime: false},
      {:opentelemetry, "~> 1.5", only: :test},
      {:plug_cowboy, "~> 2.7", only: :test, runtime: false},
      {:ssl_verify_fun, "~> 1.1.7", only: :test}
    ]
  end
end
