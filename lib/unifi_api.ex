defmodule UnifiApi do
  @moduledoc """
  Elixir client for UniFi Dream Machine APIs (Network & Protect).

  ## Quick start

      # Using application config
      client = UnifiApi.new()

      # Using explicit options
      client = UnifiApi.new(base_url: "https://192.168.0.1", api_key: "my-key")

      # Network API
      {:ok, sites} = UnifiApi.Network.Sites.list(client)
      {:ok, devices} = UnifiApi.Network.Devices.list(client, "site-uuid")

      # Protect API
      {:ok, cameras} = UnifiApi.Protect.Cameras.list(client)

  ## Configuration

  Configure via application environment or pass options to `new/1`:

      config :unifi_api,
        base_url: "https://192.168.0.1",
        api_key: "your-api-key",
        # verify_ssl: true is the default (secure-by-default since v0.4.0);
        # use cert_fingerprints for self-signed controllers.
        network_path: "/proxy/network/integration",
        protect_path: "/proxy/protect/integration"

  On UDM/UDM Pro/UDM SE the API runs behind a reverse proxy at
  `/proxy/network/integration` (Network) and `/proxy/protect/integration`
  (Protect). For Cloud Key, set both paths to `"/integration"`.

  Options passed to `new/1` override application config.
  """

  @doc """
  Creates a new API client.

  A single client works for both Network and Protect APIs. The four path
  prefixes are resolved once, here, and carried on the client struct, so a
  UDM client and a Cloud Key client can coexist in the same VM.

  ## Options

    * `:base_url` — UniFi controller URL (e.g. `"https://192.168.0.1"`)
    * `:api_key` — API key for authentication
    * `:verify_ssl` — whether to verify SSL certificates against the OS CA
      store (default: `true` since v0.4.0, secure-by-default per CWE-295 /
      OWASP A02). Set to `false` only for self-signed controllers on a
      trusted network, or pin the leaf cert with `:cert_fingerprints`.
      Ignored when `:cert_fingerprints` is set.
    * `:cert_fingerprints` — list of SHA-256 fingerprints of acceptable
      peer certificates. When set, the connection is verified by pinning
      the leaf certificate to one of these fingerprints; CA validation is
      skipped. Each entry is a hex string, optionally prefixed with
      `"sha256:"` and/or separated by colons. Example:
      `["sha256:AB:CD:..."]` or `["abcd...32-byte-hex..."]`.
    * `:style` — `:udm` (default) or `:cloud_key`. Selects the default path
      prefixes for the whole client. Use `detect/1` if you do not know which
      flavour you are talking to.
    * `:network_path` / `:protect_path` / `:v1_path` / `:protect_v1_path` —
      override an individual prefix, taking precedence over `:style`.
    * `:connect_timeout` — TCP/TLS connect timeout in ms (default 5_000).
    * `:receive_timeout` — response timeout in ms (default 30_000).
    * `:pool_timeout` — checkout timeout in ms (default 5_000).
    * `:max_retries` — retry attempts for transient failures (default 1).
    * `:finch` — the name of a Finch pool you started yourself. Mutually
      exclusive with the TLS and connect-timeout options above, which then
      belong on your own pool.

  ## Examples

      # From application config
      client = UnifiApi.new()

      # With explicit options
      client = UnifiApi.new(base_url: "https://192.168.0.1", api_key: "abc123")

      # Pin the controller's self-signed certificate
      client = UnifiApi.new(
        base_url: "https://192.168.0.1",
        api_key: "abc123",
        cert_fingerprints: ["sha256:AB:CD:EF:..."]
      )

      # Two controller flavours at once — impossible before v0.4.0, when the
      # prefixes lived in global application config.
      udm = UnifiApi.new(base_url: "https://192.168.0.1", api_key: k1, style: :udm)
      ck = UnifiApi.new(base_url: "https://192.168.0.9", api_key: k2, style: :cloud_key)

      # Same client works for both APIs
      UnifiApi.Network.Sites.list(udm)
      UnifiApi.Protect.Cameras.list(udm)
  """
  @spec new() :: Req.Request.t()
  @spec new(keyword()) :: Req.Request.t()
  defdelegate new(opts \\ []), to: UnifiApi.Client

  @typedoc """
  Result of `detect/1`.

  Feed `:style` straight back into `UnifiApi.new/1` to apply everything the
  probe learned:

      {:ok, info} = UnifiApi.detect(UnifiApi.new(base_url: url))
      client = UnifiApi.new(base_url: url, api_key: key, style: info.style)

  The prefix fields are the same values `new/1` would resolve for that style,
  exposed for callers that route paths themselves.
  """
  @type controller_info :: %{
          style: UnifiApi.Client.style(),
          network_prefix: String.t(),
          protect_prefix: String.t(),
          v1_prefix: String.t(),
          protect_v1_prefix: String.t(),
          auth_path: String.t()
        }

  @doc """
  Probes the controller and reports which path conventions to use.

  Issues `GET /` against the configured `base_url` with redirects disabled
  and applies the heuristic popularised by the
  [unpoller](https://github.com/unpoller/unpoller) project:

    * `200` — UniFi OS device (UDM, UDM Pro, UDM SE, UCK-G2). The Network
      and Protect APIs live under `/proxy/network` and `/proxy/protect`
      respectively, and login is at `/api/auth/login`.
    * `301`/`302`/`303` — standalone controller / Cloud Key. Network and
      Protect live at the root, and login is at `/api/login`.

  This heuristic is the same one unpoller uses against tens of thousands
  of deployments, but it is **not** infallible — pass `:style` (or an
  individual `:network_path` / `:protect_path` / `:v1_path` /
  `:protect_v1_path`) to `new/1` if `detect/1` mis-identifies your controller.

  ## Examples

      probe = UnifiApi.new(base_url: "https://192.168.1.1",
        cert_fingerprints: ["sha256:AB:CD:EF:..."])

      {:ok, info} = UnifiApi.detect(probe)
      # %{style: :udm,
      #   network_prefix: "/proxy/network/integration",
      #   protect_prefix: "/proxy/protect/integration",
      #   v1_prefix: "/proxy/network",
      #   protect_v1_prefix: "/proxy/protect",
      #   auth_path: "/api/auth/login"}

      # Apply everything the probe learned by naming the style. Do *not*
      # write the prefixes into application config: prefixes are resolved
      # when the client is built, so a runtime `Application.put_env/3` has no
      # effect on an existing client and races anything still in flight.
      client =
        UnifiApi.new(
          base_url: "https://192.168.1.1",
          api_key: System.fetch_env!("UNIFI_API_KEY"),
          style: info.style
        )
  """
  @spec detect(Req.Request.t()) :: {:ok, controller_info()} | {:error, UnifiApi.Error.t()}
  def detect(client) do
    # Route through `Client.raw_get/2` (not `Req.get/2` directly) so any
    # future Client-level hardening (redaction, retry policy, telemetry)
    # applies uniformly. Redirects are forced off explicitly in case the
    # caller passed a client built without `Client.new/1` (Client.new/1
    # already sets `redirect: false`).
    probe = Req.merge(client, redirect: false)

    case UnifiApi.Client.raw_get(probe, "/") do
      {:ok, %Req.Response{status: status}} when status in [301, 302, 303] ->
        {:ok, info(:cloud_key)}

      {:ok, %Req.Response{status: 200}} ->
        {:ok, info(:udm)}

      # Reconciled in v0.4.0: `detect/1` used to answer
      # `{:error, {:unexpected_status, status, body}}` while `ping/1`
      # answered `{:error, {status, body}}` for the identical situation.
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %UnifiApi.ApiError{
           status: status,
           body_preview: UnifiApi.Client.scrub_body_preview(body)
         }}

      {:error, reason} ->
        {:error, UnifiApi.Error.from_transport(reason)}
    end
  end

  @doc """
  Lightweight reachability check.

  Issues `GET /` against the controller (with redirects disabled) and
  returns `:ok` for any 2xx or 3xx — both are signs the controller is
  alive and responding. Returns `{:error, reason}` for transport
  failures or 4xx/5xx.

  Auth-agnostic: works with both the integration API key client and a
  cookie-authenticated client, since `/` is unauthenticated on every
  controller flavour.

  ## Examples

      :ok = UnifiApi.ping(client)

      case UnifiApi.ping(client) do
        :ok -> :alive
        {:error, _} -> :unreachable
      end
  """
  @spec ping(Req.Request.t()) :: :ok | {:error, UnifiApi.Error.t()}
  def ping(client) do
    # Same routing decision as `detect/1` — force redirects off for the
    # probe so 3xx surfaces as a status code rather than being followed.
    probe = Req.merge(client, redirect: false)

    case UnifiApi.Client.raw_get(probe, "/") do
      {:ok, %Req.Response{status: status}} when status in 200..399 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         %UnifiApi.ApiError{
           status: status,
           body_preview: UnifiApi.Client.scrub_body_preview(body)
         }}

      {:error, reason} ->
        {:error, UnifiApi.Error.from_transport(reason)}
    end
  end

  # Sourced from `UnifiApi.Client`'s own presets so `detect/1` and `new/1`
  # can never drift apart. Previously this map set only 2 of the 4 prefixes
  # a caller needs, so applying its recipe left `protect_v1_prefix` wrong.
  defp info(style) do
    client = UnifiApi.Client.new(style: style)

    %{
      style: style,
      network_prefix: UnifiApi.Client.network_prefix(client),
      protect_prefix: UnifiApi.Client.protect_prefix(client),
      v1_prefix: UnifiApi.Client.v1_prefix(client),
      protect_v1_prefix: UnifiApi.Client.protect_v1_prefix(client),
      auth_path: auth_path(style)
    }
  end

  defp auth_path(:udm), do: "/api/auth/login"
  defp auth_path(:cloud_key), do: "/api/login"
end
