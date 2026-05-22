defmodule OpentelemetryPlug.MixProject do
  use Mix.Project

  @version "1.3.1"

  def project do
    [
      app: :otel_plug,
      version: @version,
      elixir: "~> 1.10",
      docs: [
        extras: ["README.md"],
        main: "readme",
        source_ref: "v#{@version}"
      ],
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      deps: deps(),
      package: package(),
      description: description(),
      source_url: "https://github.com/bancolombia/opentelemetry_plug"
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.xml": :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test
      ]
    ]
  end

  defp description() do
    "An OpenTelemetry Plug middleware for instrumenting HTTP requests in Elixir applications using the Plug framework."
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["juancgalvis"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/bancolombia/opentelemetry_plug"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_semantic_conventions, "~> 1.27"},
      {:plug, "~> 1.19"},
      {:otel_http, "~> 0.2"},
      {:telemetry, "~> 1.4"},
      # Test dependencies
      {:mock, "~> 0.3", only: :test},
      {:excoveralls, "~> 0.18", [only: [:dev, :test]]},
      {:hackney, "~> 4.0", only: :test, runtime: false},
      {:plug_cowboy, "~> 2.8", only: :test, runtime: false},
      {:ssl_verify_fun, "~> 1.1", only: :test},
      {:sobelow, "~> 0.14", [only: [:dev, :test], runtime: false]},
      {:credo, "~> 1.7", [only: [:dev, :test], runtime: false]},
      {:dialyxir, "~> 1.4", [only: [:dev, :test], runtime: false]},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
