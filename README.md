# OpentelemetryPlug

[![hex.pm version](https://img.shields.io/hexpm/v/otel_plug.svg?style=flat)](https://hex.pm/packages/otel_plug)
[![hex.pm downloads](https://img.shields.io/hexpm/dt/otel_plug.svg?style=flat)](https://hex.pm/packages/otel_plug)
[![Scorecards supply-chain security](https://github.com/bancolombia/opentelemetry_plug/actions/workflows/scorecards-analysis.yml/badge.svg)](https://github.com/bancolombia/opentelemetry_plug/actions/workflows/scorecards-analysis.yml)

An OpenTelemetry Plug middleware for instrumenting HTTP requests in Elixir applications using the Plug framework. This package automatically creates spans for incoming HTTP requests, capturing essential attributes such as HTTP method, URL, status code, and more.

## Installation

The package can be installed by adding `otel_plug` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:otel_plug, "~> 1.3"}, # Check for latest version on Hex.pm
  ]
end
```

# Exclude routes

You can ignore specific routes to avoid traces generation (it always will generate traces when error)

```elixir
config :opentelemetry_plug,
  ignored_routes: ["/health", "/metrics"],
  extra_request_headers_to_trace: [],
  extra_response_headers_to_trace: [],
  # default request headers to trace
  # request_headers_to_trace: [
  #   "accept",
  #   "content-type",
  #   "origin",
  #   "traceparent",
  #   "tracestate",
  #   "x-forwarded-for",
  #   "x-forwarded-proto",
  #   "x-request-id"
  # ],
  # default response headers to trace
  # response_headers_to_trace: [
  #  "content-type",
  #  "x-request-id"
  # ]
```

