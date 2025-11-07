# OpentelemetryPlug

An OpenTelemetry Plug middleware for instrumenting HTTP requests in Elixir applications using the Plug framework. This package automatically creates spans for incoming HTTP requests, capturing essential attributes such as HTTP method, URL, status code, and more.

## Installation

The package can be installed by adding `opentelemetry_plug` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:opentelemetry_plug, git: "https://github.com/bancolombia/opentelemetry_plug.git", tag: "v1.1.1"}, # Check for latest tag on GitHub
  ]
end
```

# Exclude routes

You can ignore specific routes to avoid traces generation (it always will generate traces when error)

```elixir
config :opentelemetry_plug,
  ignored_routes: ["/health", "/metrics"]
```

