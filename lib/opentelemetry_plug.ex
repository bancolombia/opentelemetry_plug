defmodule OpentelemetryPlug do
  @moduledoc """
  Telemetry handler for creating OpenTelemetry Spans from Plug events.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias OpenTelemetry.SemConv.{
    ClientAttributes,
    HTTPAttributes,
    NetworkAttributes,
    ServerAttributes,
    URLAttributes,
    UserAgentAttributes
  }

  alias OpenTelemetry.SemConv.Incubating.HTTPAttributes, as: IncubatingHTTPAttributes

  alias OpenTelemetry.Span

  @dialyzer {:nowarn_function, client_info: 3}

  @default_request_headers_to_trace [
    "accept",
    "content-type",
    "origin",
    "traceparent",
    "tracestate",
    "x-forwarded-for",
    "x-forwarded-proto",
    "x-request-id",
    "x-sre-trace"
  ]

  @default_response_headers_to_trace [
    "content-type",
    "x-request-id"
  ]

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
      register_before_send(conn, fn conn ->
        case OpentelemetryPlug.body_size(conn, :response) do
          nil ->
            :ok

          size ->
            Tracer.set_attribute(IncubatingHTTPAttributes.http_response_body_size(), size)
        end

        merge_resp_headers(conn, :otel_propagator_text_map.inject([]))
      end)
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
    # http.response.status_code.
    if is_error? and disabled? do
      setup_span(conn, route)
    end

    if is_error? do
      Tracer.set_status(OpenTelemetry.status(:error, ""))
    end

    if record? do
      extract_headers(conn, :response)
      |> Enum.each(fn {key, value} -> Tracer.set_attribute(key, value) end)

      Tracer.set_attribute(HTTPAttributes.http_response_status_code(), conn.status)

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
    Tracer.set_attribute(HTTPAttributes.http_response_status_code(), 500)
    Tracer.end_span()
    restore_parent_ctx()
  end

  defp setup_span(conn, route) do
    save_parent_ctx()
    # setup OpenTelemetry context based on request headers
    :otel_propagator_text_map.extract(conn.req_headers)

    span_name = span_name("#{route}", conn.request_path)
    peer_data = Plug.Conn.get_peer_data(conn)
    peer_address = to_string(:inet_parse.ntoa(Map.get(peer_data, :address)))

    {protocol, protocol_version} = protocol_info(conn.adapter)
    {client_address, client_port} = client_info(conn, peer_address, peer_data.port)

    attributes =
      %{
        ClientAttributes.client_port() => client_port,
        ClientAttributes.client_address() => client_address,
        HTTPAttributes.http_request_method() => conn.method,
        HTTPAttributes.http_route() => route,
        NetworkAttributes.network_local_address() => to_string(:inet_parse.ntoa(conn.remote_ip)),
        NetworkAttributes.network_protocol_name() => protocol,
        NetworkAttributes.network_protocol_version() => protocol_version,
        NetworkAttributes.network_peer_address() => peer_address,
        NetworkAttributes.network_transport() => "tcp",
        ServerAttributes.server_address() => conn.host,
        ServerAttributes.server_port() => conn.port,
        URLAttributes.url_path() => conn.request_path,
        URLAttributes.url_scheme() => conn.scheme
      }
      |> Map.merge(optional_attributes(conn))
      |> Map.merge(extract_headers(conn, :request))

    span_ctx = Tracer.start_span(span_name, %{attributes: attributes, kind: :server})

    Tracer.set_current_span(span_ctx)
  end

  defp span_name("/*_path", path), do: path
  defp span_name(route, _path), do: route

  defp extract_headers(conn, type) do
    headers_to_trace(type)
    |> Enum.map(&map_header(&1, conn, type))
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.into(%{})
  end

  defp map_header("x-sre-trace", conn, type) do
    value = header_or_nil(conn, "x-sre-trace", type)
    {"x-sre-trace", value}
  end

  defp map_header(header, conn, type) do
    value = header_or_nil(conn, header, type)
    {"http.#{type}.header.#{String.downcase(header)}", value}
  end

  defp header_or_nil(conn, header, :request) do
    Plug.Conn.get_req_header(conn, String.downcase(header))
    |> clean_header()
  end

  defp header_or_nil(conn, header, :response) do
    Plug.Conn.get_resp_header(conn, String.downcase(header))
    |> clean_header()
  end

  defp clean_header(header) do
    case header do
      [] ->
        nil

      ["" | _] ->
        nil

      [value | _] ->
        value
    end
  end

  defp optional_attributes(conn) do
    %{
      UserAgentAttributes.user_agent_original() => &header_or_nil(&1, "user-agent", :request),
      IncubatingHTTPAttributes.http_request_body_size() => &body_size(&1, :request),
      URLAttributes.url_query() => &get_query_string/1
    }
    |> Enum.map(fn {attr, fun} -> {attr, fun.(conn)} end)
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.into(%{})
  end

  defp client_info(conn, peer_ip, peer_port) do
    case :otel_http.extract_client_info(conn.req_headers) do
      %{ip: :undefined, port: :undefined} -> {peer_ip, peer_port}
      %{ip: ip, port: :undefined} -> {ip, peer_port}
      %{ip: :undefined, port: port} -> {peer_ip, port}
      %{ip: ip, port: port} -> {ip, port}
    end
  end

  defp get_query_string(conn) do
    case conn.query_string do
      "" -> nil
      qs -> qs
    end
  end

  def body_size(conn, type) do
    case header_or_nil(conn, "content-length", type) do
      nil ->
        body_size_from_conn(conn, type)

      value ->
        case Integer.parse(value) do
          {size, _} -> size
          :error -> nil
        end
    end
  end

  defp body_size_from_conn(conn, type) do
    case type do
      :request ->
        nil

      :response ->
        case conn.resp_body do
          nil -> nil
          body -> IO.iodata_length(body)
        end
    end
  end

  defp protocol_info({_adapter_name, meta}) do
    version = Map.get(meta, :version)
    map_http_version(version)
  end

  defp map_http_version(:"HTTP/1.0"), do: {"http", :"1.0"}
  defp map_http_version(:"HTTP/1"), do: {"http", :"1.0"}
  defp map_http_version(:"HTTP/1.1"), do: {"http", :"1.1"}
  defp map_http_version(:"HTTP/2.0"), do: {"http", :"2.0"}
  defp map_http_version(:"HTTP/2"), do: {"http", :"2.0"}
  defp map_http_version(:"HTTP/3.0"), do: {"http", :"3.0"}
  defp map_http_version(:"HTTP/3"), do: {"http", :"3.0"}
  defp map_http_version(:SPDY), do: {"SPDY", :"2"}
  defp map_http_version(:QUIC), do: {"QUIC", :"3"}
  defp map_http_version(_other), do: {"", :""}

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
    if not Enum.empty?(routes) do
      Logger.warning("OpentelemetryPlug is ignoring the following routes: #{inspect(routes)}")
    end

    routes
  end

  defp headers_to_trace(:request) do
    Application.get_env(
      :opentelemetry_plug,
      :request_headers_to_trace,
      @default_request_headers_to_trace
    ) ++
      Application.get_env(:opentelemetry_plug, :extra_request_headers_to_trace, [])
  end

  defp headers_to_trace(:response) do
    Application.get_env(
      :opentelemetry_plug,
      :response_headers_to_trace,
      @default_response_headers_to_trace
    ) ++
      Application.get_env(:opentelemetry_plug, :extra_response_headers_to_trace, [])
  end
end
