import Config

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: {:otel_exporter_stdout, []}

config :opentelemetry_plug,
  ignored_routes: ["/health"]
