defmodule OpentelemetryPlug do
  @moduledoc """
  Telemetry handler for creating OpenTelemetry Spans from Plug events.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  alias OpenTelemetry.Span

  defmodule Propagation do
    @moduledoc """
    Adds OpenTelemetry context propagation headers to the Plug response.

    ### WARNING

    These context headers are potentially dangerous to expose to third-parties.
    W3C recommends against including them except in cases where both client and
    server participate in the trace.

    See https://www.w3.org/TR/trace-context/#other-risks for more information.
    """

    @behaviour Plug
    import Plug.Conn, only: [register_before_send: 2, merge_resp_headers: 2]

    @impl true
    def init(opts) do
      opts
    end

    @impl true
    def call(conn, _opts) do
      register_before_send(conn, &merge_resp_headers(&1, :otel_propagator_text_map.inject([])))
    end
  end

  @doc """
  Attaches the OpentelemetryPlug handler to your Plug.Router events. This
  should be called from your application behaviour on startup.

  Example:

  OpentelemetryPlug.setup()

  """
  def setup do
    ignored = ignored_routes()

    :telemetry.attach(
      {__MODULE__, :plug_router_start},
      [:plug, :router_dispatch, :start],
      &__MODULE__.handle_start/4,
      ignored
    )

    :telemetry.attach(
      {__MODULE__, :plug_router_stop},
      [:plug, :router_dispatch, :stop],
      &__MODULE__.handle_stop/4,
      ignored
    )

    :telemetry.attach(
      {__MODULE__, :plug_router_exception},
      [:plug, :router_dispatch, :exception],
      &__MODULE__.handle_exception/4,
      ignored
    )
  end

  @spec handle_start(
          any,
          any,
          %{:conn => Plug.Conn.t(), :route => any, optional(any) => any},
          any
        ) ::
          :undefined
          | {:span_ctx, non_neg_integer, non_neg_integer, integer,
             [
               {binary | maybe_improper_list(any, binary | []),
                binary | maybe_improper_list(any, binary | [])}
             ], false | true | :undefined, boolean, false | true | :undefined,
             :undefined | {atom, any}}
  @doc false
  def handle_start(_, _measurements, %{conn: conn, route: route}, ignored) do
    if not Map.has_key?(ignored, route) do
      setup_span(conn, route)
    end
  end

  @doc false
  def handle_stop(_, _measurements, %{conn: conn, route: route}, ignored) do
    disabled? = Map.has_key?(ignored, route)
    is_error? = conn.status >= 400
    record? = not disabled? or is_error?
    # For HTTP status codes in the 4xx and 5xx ranges, as well as any other
    # code the client failed to interpret, status MUST be set to Error.
    #
    # Don't set the span status description if the reason can be inferred from
    # http.status_code.
    if is_error? and disabled? do
      setup_span(conn, route)
    end

    if is_error? do
      Tracer.set_status(OpenTelemetry.status(:error, ""))
    end

    if record? do
      Tracer.set_attribute(:"http.status_code", conn.status)

      Tracer.end_span()
      restore_parent_ctx()
    end
  end

  @doc false
  def handle_exception(_, _measurements, %{conn: conn, route: route} = metadata, ignored) do
    if Map.has_key?(ignored, route) do
      setup_span(conn, route)
    end

    %{kind: kind, stacktrace: stacktrace} = metadata
    # This metadata key changed from :error to :reason in Plug 1.10.3
    reason = metadata[:reason] || metadata[:error]

    exception = Exception.normalize(kind, reason, stacktrace)

    Span.record_exception(
      Tracer.current_span_ctx(),
      exception,
      stacktrace
    )

    Tracer.set_status(OpenTelemetry.status(:error, Exception.message(exception)))
    Tracer.set_attribute(:"http.status_code", 500)
    Tracer.end_span()
    restore_parent_ctx()
  end

  defp setup_span(conn, route) do
    save_parent_ctx()
    # setup OpenTelemetry context based on request headers
    :otel_propagator_text_map.extract(conn.req_headers)

    span_name = "#{route}"

    peer_data = Plug.Conn.get_peer_data(conn)

    user_agent = header_or_empty(conn, "User-Agent")
    host = header_or_empty(conn, "Host")
    peer_ip = Map.get(peer_data, :address)

    attributes =
      [
        "http.target": conn.request_path,
        "http.host": conn.host,
        "http.scheme": conn.scheme,
        "http.flavor": http_flavor(conn.adapter),
        "http.route": route,
        "http.user_agent": user_agent,
        "http.method": conn.method,
        "net.peer.ip": to_string(:inet_parse.ntoa(peer_ip)),
        "net.peer.port": peer_data.port,
        "net.peer.name": host,
        "net.transport": "IP.TCP",
        "net.host.ip": to_string(:inet_parse.ntoa(conn.remote_ip)),
        "net.host.port": conn.port
      ] ++ optional_attributes(conn)

    span_ctx = Tracer.start_span(span_name, %{attributes: attributes, kind: :server})

    Tracer.set_current_span(span_ctx)
  end

  defp header_or_empty(conn, header) do
    case Plug.Conn.get_req_header(conn, header) do
      [] ->
        ""

      [host | _] ->
        host
    end
  end

  defp optional_attributes(conn) do
    ["http.client_ip": &client_ip/1, "http.server_name": &server_name/1]
    |> Enum.map(fn {attr, fun} -> {attr, fun.(conn)} end)
    |> Enum.reject(&is_nil(elem(&1, 1)))
  end

  defp client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [] ->
        nil

      [host | _] ->
        host
    end
  end

  defp server_name(_) do
    Application.get_env(:opentelemetry_plug, :server_name, nil)
  end

  defp http_flavor({_adapter_name, meta}) do
    version = Map.get(meta, :version)
    map_http_version(version)
  end

  defp map_http_version(:"HTTP/1.0"), do: :"1.0"
  defp map_http_version(:"HTTP/1"), do: :"1.0"
  defp map_http_version(:"HTTP/1.1"), do: :"1.1"
  defp map_http_version(:"HTTP/2.0"), do: :"2.0"
  defp map_http_version(:"HTTP/2"), do: :"2.0"
  defp map_http_version(:"HTTP/3.0"), do: :"3.0"
  defp map_http_version(:"HTTP/3"), do: :"3.0"
  defp map_http_version(:SPDY), do: :SPDY
  defp map_http_version(:QUIC), do: :QUIC
  defp map_http_version(_other), do: ""

  @ctx_key {__MODULE__, :parent_ctx}
  defp save_parent_ctx do
    ctx = Tracer.current_span_ctx()
    Process.put(@ctx_key, ctx)
  end

  defp restore_parent_ctx do
    ctx = Process.get(@ctx_key, :undefined)
    Process.delete(@ctx_key)
    Tracer.set_current_span(ctx)
  end

  defp ignored_routes do
    Application.get_env(:opentelemetry_plug, :ignored_routes, [])
    |> log_ignored_route()
    |> Enum.into(%{}, fn key -> {key, true} end)
  end

  defp log_ignored_route(routes) do
    if Enum.count(routes) > 0 do
      Logger.warning("OpentelemetryPlug is ignoring the following routes: #{inspect(routes)}")
    end

    routes
  end
end
