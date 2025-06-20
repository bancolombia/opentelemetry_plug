# OpentelemetryPlug

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `opentelemetry_plug` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:opentelemetry_plug, "~> 0.1.0"}
  ]
end
```

# Exclude routes

You can ignore specific router to avoid traces generation (it always will generate traces when error)

```elixir
config :opentelemetry_plug,
  ignored_routes: ["health"]
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/opentelemetry_plug](https://hexdocs.pm/opentelemetry_plug).

