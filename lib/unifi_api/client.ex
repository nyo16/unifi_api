defmodule UnifiApi.Client do
  @moduledoc """
  HTTP client wrapper for UniFi API requests.

  This module handles authentication, base URL construction, SSL settings,
  pagination parameters, and response normalization. All API modules delegate
  to this client for HTTP operations.

  Typically you create a client via `UnifiApi.new/1` and pass it to API functions:

      client = UnifiApi.new(base_url: "https://192.168.1.1", api_key: "my-key")
      UnifiApi.Network.Sites.list(client)
  """

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, term()}

  @doc """
  Creates a new API client.

  See `UnifiApi.new/1` for options and examples.
  """
  @spec new(keyword()) :: client()
  def new(opts \\ []) do
    base_url = opts[:base_url] || Application.get_env(:unifi_api, :base_url)
    api_key = opts[:api_key] || Application.get_env(:unifi_api, :api_key)

    Req.new(
      base_url: base_url,
      headers: [{"x-api-key", api_key}],
      connect_options: tls_connect_opts(opts),
      redirect: false
    )
  end

  defp tls_connect_opts(opts) do
    fingerprints =
      opts[:cert_fingerprints] ||
        Application.get_env(:unifi_api, :cert_fingerprints, [])

    verify_ssl =
      Keyword.get(opts, :verify_ssl, Application.get_env(:unifi_api, :verify_ssl, false))

    cond do
      fingerprints != [] ->
        [transport_opts: fingerprint_pinning_opts(fingerprints)]

      verify_ssl ->
        []

      true ->
        [transport_opts: [verify: :verify_none]]
    end
  end

  defp fingerprint_pinning_opts(fingerprints) do
    decoded = Enum.map(fingerprints, &decode_fingerprint!/1)

    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      verify_fun: {build_fingerprint_verify_fun(decoded), nil}
    ]
  end

  defp build_fingerprint_verify_fun(decoded_fps) do
    fn
      _cert, {:bad_cert, _reason}, state -> {:valid, state}
      _cert, {:extension, _ext}, state -> {:unknown, state}
      cert, :valid, state -> check_fingerprint(cert, decoded_fps, state)
      cert, :valid_peer, state -> check_fingerprint(cert, decoded_fps, state)
    end
  end

  defp check_fingerprint(otp_cert, allowed, state) do
    der = :public_key.pkix_encode(:OTPCertificate, otp_cert, :otp)
    fp = :crypto.hash(:sha256, der)

    if fp in allowed,
      do: {:valid, state},
      else: {:fail, :fingerprint_mismatch}
  end

  @doc false
  @spec decode_fingerprint!(String.t()) :: <<_::256>>
  def decode_fingerprint!(fingerprint) when is_binary(fingerprint) do
    normalized =
      fingerprint
      |> String.trim()
      |> String.downcase()
      |> String.trim_leading("sha256:")
      |> String.replace(":", "")

    case Base.decode16(normalized, case: :lower) do
      {:ok, <<bin::binary-size(32)>>} ->
        bin

      _ ->
        raise ArgumentError,
              "invalid SHA-256 cert fingerprint: #{inspect(fingerprint)} " <>
                "(expected 64 hex chars, optionally prefixed with \"sha256:\" " <>
                "and/or separated by colons)"
    end
  end

  @doc """
  Returns the Network API path prefix.

  Defaults to `"/proxy/network/integration"` (UDM). For non-UDM setups
  (Cloud Key), configure `network_path: "/integration"` in application config.
  """
  @spec network_prefix() :: String.t()
  def network_prefix do
    Application.get_env(:unifi_api, :network_path, "/proxy/network/integration")
  end

  @doc """
  Returns the Protect API path prefix.

  Defaults to `"/proxy/protect/integration"` (UDM). For non-UDM setups
  (Cloud Key), configure `protect_path: "/integration"` in application config.
  """
  @spec protect_prefix() :: String.t()
  def protect_prefix do
    Application.get_env(:unifi_api, :protect_path, "/proxy/protect/integration")
  end

  @doc """
  Returns the legacy v1 Network API path prefix.

  This is the prefix for the older `/api/s/{site}/...` and
  `/v2/api/site/{site}/...` endpoints (events, alarms, IDS, anomalies,
  historical clients, DPI, topology, etc.) that Ubiquiti has not yet
  exposed under `x-api-key`. These endpoints require cookie + CSRF auth
  via `UnifiApi.Auth.Cookie`.

  Defaults to `"/proxy/network"` (UDM). For Cloud Key / standalone
  controllers, configure `v1_path: ""` in application config.
  """
  @spec v1_prefix() :: String.t()
  def v1_prefix do
    Application.get_env(:unifi_api, :v1_path, "/proxy/network")
  end

  @doc """
  Performs a GET request.

  ## Options

    * `:offset` — pagination offset (default: 0)
    * `:limit` — page size (default: 25, max: 200)
    * `:filter` — UniFi filter expression (e.g. `"type.eq(WIRELESS)"`)

  ## Examples

      Client.get(client, "/v1/sites")
      Client.get(client, "/v1/sites/abc/clients", limit: 50, offset: 100)
      Client.get(client, "/v1/sites/abc/clients", filter: "type.eq(WIRED)")
  """
  @spec get(client(), String.t(), keyword()) :: response()
  def get(client, path, opts \\ []) do
    params = build_params(opts)

    client
    |> Req.get(url: path, params: params)
    |> handle_response()
  end

  @doc """
  Performs a GET request against a legacy v1 endpoint and unwraps the
  `%{"meta" => %{"rc" => "ok"}, "data" => [...]}` envelope.

  Used by `UnifiApi.Network.Events`, `Alarms`, `ClientsLive`, etc. — all
  the endpoints that require cookie + CSRF auth via `UnifiApi.Auth.Cookie`.

  Returns:

    * `{:ok, data}` when `meta.rc == "ok"` (or no envelope is present).
    * `{:error, {:unifi_error, msg}}` when the controller returns
      `meta.rc == "error"` (e.g. `meta.msg = "api.err.LoginRequired"`).
    * `{:error, reason}` for transport / non-2xx responses, same as `get/3`.

  ## Options

  Same as `get/3`. The `:params` option is the most useful here:

      Client.get_v1(client, "/proxy/network/api/s/default/stat/event",
        params: [_limit: 100, within: 24])
  """
  @spec get_v1(client(), String.t(), keyword()) :: response()
  def get_v1(client, path, opts \\ []) do
    with {:ok, body} <- get(client, path, opts) do
      unwrap_v1(body)
    end
  end

  defp unwrap_v1(%{"meta" => %{"rc" => "ok"}, "data" => data}), do: {:ok, data}

  defp unwrap_v1(%{"meta" => %{"rc" => "error"} = meta}),
    do: {:error, {:unifi_error, meta["msg"] || "unknown"}}

  defp unwrap_v1(%{"data" => data}), do: {:ok, data}
  defp unwrap_v1(other), do: {:ok, other}

  @doc """
  Performs a POST request with a JSON body.

  ## Examples

      Client.post(client, "/v1/sites/abc/networks", %{name: "Guest"})
  """
  @spec post(client(), String.t(), term(), keyword()) :: response()
  def post(client, path, body, opts \\ []) do
    params = build_params(opts)

    client
    |> Req.post(url: path, json: body, params: params)
    |> handle_response()
  end

  @doc """
  Performs a PUT request with a JSON body.

  ## Examples

      Client.put(client, "/v1/sites/abc/networks/net-1", %{name: "Updated"})
  """
  @spec put(client(), String.t(), term(), keyword()) :: response()
  def put(client, path, body, opts \\ []) do
    params = build_params(opts)

    client
    |> Req.put(url: path, json: body, params: params)
    |> handle_response()
  end

  @doc """
  Performs a PATCH request with a JSON body.

  ## Examples

      Client.patch(client, "/v1/cameras/cam-1", %{name: "Front Door"})
  """
  @spec patch(client(), String.t(), term(), keyword()) :: response()
  def patch(client, path, body, opts \\ []) do
    params = build_params(opts)

    client
    |> Req.patch(url: path, json: body, params: params)
    |> handle_response()
  end

  @doc """
  Performs a DELETE request.

  ## Examples

      Client.delete(client, "/v1/sites/abc/networks/net-1")
  """
  @spec delete(client(), String.t(), keyword()) :: response()
  def delete(client, path, opts \\ []) do
    params = build_params(opts)

    client
    |> Req.delete(url: path, params: params)
    |> handle_response()
  end

  @doc """
  Performs a GET request returning the raw (non-JSON-decoded) body.

  Used for binary responses like camera snapshots.

  ## Options

    * `:high_quality` — request high-quality snapshot (boolean)

  ## Examples

      {:ok, jpeg_binary} = Client.get_raw(client, "/v1/cameras/cam-1/snapshot")
      {:ok, jpeg_binary} = Client.get_raw(client, "/v1/cameras/cam-1/snapshot", high_quality: true)
  """
  @spec get_raw(client(), String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def get_raw(client, path, opts \\ []) do
    params = build_params(opts)

    case Req.get(client, url: path, params: params) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{} = resp} ->
        {:error, error_from_response(resp)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a lazy stream that automatically paginates through results.

  Uses `Stream.resource/3` to fetch pages on demand. Each page requests
  up to `:limit` items (default 200, the API maximum). The stream halts
  when a page returns fewer items than the limit.

  Raises on API errors.

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression

  ## Examples

      # Stream all items
      Client.stream(client, "/v1/sites/abc/devices")
      |> Enum.to_list()

      # Stream with filter, take first 10
      Client.stream(client, "/v1/sites/abc/clients", filter: "type.eq(WIRELESS)")
      |> Enum.take(10)

      # Count all wireless clients across pages
      Client.stream(client, "/v1/sites/abc/clients", filter: "type.eq(WIRELESS)")
      |> Enum.count()
  """
  @spec stream(client(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, path, opts \\ []) do
    page_size = opts[:limit] || 200
    base_opts = Keyword.take(opts, [:filter])

    Stream.resource(
      fn -> 0 end,
      fn
        :halt ->
          {:halt, :done}

        offset ->
          request_opts = Keyword.merge(base_opts, limit: page_size, offset: offset)

          case get(client, path, request_opts) do
            {:ok, items} when is_list(items) ->
              if length(items) < page_size,
                do: {items, :halt},
                else: {items, offset + page_size}

            {:error, reason} ->
              raise UnifiApi.StreamError, reason: reason, path: path

            {:ok, non_list} ->
              raise UnifiApi.StreamError,
                reason: {:unexpected_response, non_list},
                path: path
          end
      end,
      fn _state -> :ok end
    )
  end

  @doc """
  Generic page-number paginator for v2 endpoints that don't fit
  `stream/3` or `stream_v1/3`.

  Takes a `fetch_page` function that receives the current cursor and
  returns `{:ok, list}` (the page of items) or `{:error, reason}`.
  Halts when a page returns fewer than `:limit` items.

  ## Options

    * `:limit` — items per page (default 500). Used to detect the
      last page (a short page halts the stream).
    * `:start_at` — initial cursor value (default 0; for endpoints
      that page from 1 set `start_at: 1`).
    * `:increment` — how much to advance the cursor between pages.
      Use `1` for `pageNumber`-style paging, or set to `:limit` (the
      page size) for offset-style paging.

  ## Examples

      Client.stream_paged(
        fn page ->
          Client.get_v1(client, "/v2/api/site/default/system-log/all",
            params: [pageSize: 500, pageNumber: page])
        end,
        limit: 500
      )

  Used by `UnifiApi.Network.ClientsHistory.stream/3` and
  `UnifiApi.Network.SystemLog.stream/3`.
  """
  @spec stream_paged((non_neg_integer() -> response()), keyword()) :: Enumerable.t()
  def stream_paged(fetch_page, opts \\ []) when is_function(fetch_page, 1) do
    page_size = opts[:limit] || 500
    initial = Keyword.get(opts, :start_at, 0)
    increment = Keyword.get(opts, :increment, 1)

    Stream.resource(
      fn -> initial end,
      fn
        :halt ->
          {:halt, :done}

        cursor ->
          case fetch_page.(cursor) do
            {:ok, items} when is_list(items) ->
              if length(items) < page_size,
                do: {items, :halt},
                else: {items, cursor + increment}

            {:error, reason} ->
              raise UnifiApi.StreamError, reason: reason, path: "stream_paged"

            {:ok, non_list} ->
              raise UnifiApi.StreamError,
                reason: {:unexpected_response, non_list},
                path: "stream_paged"
          end
      end,
      fn _state -> :ok end
    )
  end

  @doc """
  Like `stream/3` but for legacy v1 endpoints.

  Pages on `_start` / `_limit` (the v1 convention) rather than
  `offset` / `limit`, and unwraps the v1 response envelope via
  `get_v1/3`. Used by `UnifiApi.Network.Events.stream/3`,
  `Alarms.stream/3`, etc.

  ## Options

    * `:limit` — items per page (default: 500, the typical v1 cap)
    * `:params` — additional query params merged on every request
      (e.g. `[within: 24]` to time-window the entire stream)
  """
  @spec stream_v1(client(), String.t(), keyword()) :: Enumerable.t()
  def stream_v1(client, path, opts \\ []) do
    page_size = opts[:limit] || 500
    base_params = Keyword.get(opts, :params, [])

    Stream.resource(
      fn -> 0 end,
      fn
        :halt ->
          {:halt, :done}

        start ->
          params = base_params ++ [_start: start, _limit: page_size]

          case get_v1(client, path, params: params) do
            {:ok, items} when is_list(items) ->
              if length(items) < page_size,
                do: {items, :halt},
                else: {items, start + page_size}

            {:error, reason} ->
              raise UnifiApi.StreamError, reason: reason, path: path

            {:ok, non_list} ->
              raise UnifiApi.StreamError,
                reason: {:unexpected_response, non_list},
                path: path
          end
      end,
      fn _state -> :ok end
    )
  end

  defp build_params(opts) do
    extra = Keyword.get(opts, :params, [])

    extra
    |> maybe_add(:offset, opts[:offset])
    |> maybe_add(:limit, opts[:limit])
    |> maybe_add(:filter, opts[:filter])
    |> maybe_add(:highQuality, opts[:high_quality])
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, value), do: [{key, value} | params]

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{} = resp}) do
    {:error, error_from_response(resp)}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp error_from_response(%Req.Response{status: 429, body: body} = resp) do
    %UnifiApi.RateLimitError{
      retry_after: parse_retry_after(Req.Response.get_header(resp, "retry-after")),
      status: 429,
      body: body
    }
  end

  defp error_from_response(%Req.Response{status: 401, body: body}) do
    %UnifiApi.AuthError{status: 401, body: body, reason: :unauthorized}
  end

  defp error_from_response(%Req.Response{status: 403, body: body}) do
    %UnifiApi.AuthError{status: 403, body: body, reason: :forbidden}
  end

  defp error_from_response(%Req.Response{status: status, body: body}) do
    {status, body}
  end

  # Parses Retry-After header (RFC 7231 §7.1.3): seconds or HTTP-date.
  # Falls back to 60s. Clamped to 1..300.
  defp parse_retry_after([]), do: 60

  defp parse_retry_after([value | _]) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} ->
        clamp_retry_after(seconds)

      _ ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _} -> clamp_retry_after(DateTime.diff(dt, DateTime.utc_now()))
          _ -> 60
        end
    end
  end

  defp clamp_retry_after(seconds) when seconds <= 1, do: 1
  defp clamp_retry_after(seconds) when seconds >= 300, do: 300
  defp clamp_retry_after(seconds), do: seconds
end
