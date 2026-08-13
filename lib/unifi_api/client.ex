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

  # Ceiling on any sleep the *server* gets to dictate. Applied to both the
  # Req-level retry (`retry_transient/2`) and the in-stream `RateLimitError`
  # backoff, so a hostile `Retry-After` cannot park a caller indefinitely.
  @retry_after_ceiling_seconds 300
  @retry_after_default_seconds 60

  @type client :: Req.Request.t()
  @type response :: {:ok, term()} | {:error, UnifiApi.Error.t()}

  @typedoc "Which of the controller's four API surfaces a path belongs to."
  @type api :: :network | :protect | :network_v1 | :protect_v1

  @typedoc "Controller flavour. Decides the default path prefixes."
  @type style :: :udm | :cloud_key

  @apis [:network, :protect, :network_v1, :protect_v1]
  @default_style :udm

  # api -> {`new/1` option key, legacy `Application` env key}
  @prefix_keys [
    network: {:network_path, :network_path},
    protect: {:protect_path, :protect_path},
    network_v1: {:v1_path, :v1_path},
    protect_v1: {:protect_v1_path, :protect_v1_path}
  ]

  @presets %{
    udm: %{
      network: "/proxy/network/integration",
      protect: "/proxy/protect/integration",
      network_v1: "/proxy/network",
      protect_v1: "/proxy/protect"
    },
    cloud_key: %{
      network: "/integration",
      protect: "/integration",
      network_v1: "",
      protect_v1: "/protect"
    }
  }

  # Resource IDs interpolated into API paths are restricted to this
  # charset and length to close CWE-22 / OWASP A03 (path traversal via
  # crafted ids — e.g. `"../"`, `"?a=b"`, `"#"`, `"a/b/c"`). The check
  # runs at the boundary of every endpoint module before composition.
  @id_max_length 64
  @id_pattern ~r/^[A-Za-z0-9_-]{1,64}\z/

  # `:bad_cert` reasons that fingerprint pinning is allowed to override:
  # a self-signed leaf, an unbuildable chain, and an expired cert. Each is
  # overridden *only* when the presented certificate matches a pinned
  # fingerprint (see `build_fingerprint_verify_fun/2`). Every other reason
  # (revoked, key/usage violations, malformed issuer, ...) fails the
  # handshake unconditionally.
  @weak_bad_cert_reasons ~w(selfsigned_peer unknown_ca cert_expired)a

  @doc """
  Validates a resource ID before it is interpolated into a request path.

  IDs must be a binary whose characters are all in `[A-Za-z0-9_-]` and
  whose length is 1..64. Raises `ArgumentError` at the boundary so a
  bad id never reaches URL composition (CWE-22 / OWASP A03).

  ## Examples

      iex> UnifiApi.Client.validate_id!("default")
      "default"

      iex> UnifiApi.Client.validate_id!("cam-1")
      "cam-1"

  """
  @spec validate_id!(binary()) :: binary() | no_return()
  def validate_id!(id) when is_binary(id) do
    if Regex.match?(@id_pattern, id) do
      id
    else
      raise ArgumentError,
            "invalid resource id: #{inspect(id)} " <>
              "(must be 1..#{@id_max_length} chars in [A-Za-z0-9_-])"
    end
  end

  def validate_id!(id) do
    raise ArgumentError,
          "invalid resource id: #{inspect(id)} (must be a string)"
  end

  @doc false
  @spec validate_ids!([binary()]) :: :ok | no_return()
  def validate_ids!(ids) when is_list(ids) do
    Enum.each(ids, &validate_id!/1)
    :ok
  end

  @doc """
  Creates a new API client.

  See `UnifiApi.new/1` for options and examples.

  ## Production-safe defaults (v0.4.0)

    * `:receive_timeout` — 30_000ms (Req default is 15s × 3 retries).
    * `:connect_timeout` — 5_000ms. Mint's default is 30s, so against a
      black-holed controller IP a single `get/3` used to block 30s, retry,
      and block another 30s — ~61s, with no way to shorten it. Health-check
      loops need sub-minute detection.
    * `:pool_timeout` — 5_000ms (Req default 5s).
    * `:max_retries` — 1 (Req default 3 — too many for a controller that
      rotates CSRF mid-request).
    * retry backoff is clamped to #{@retry_after_ceiling_seconds}s
      even when the controller asks for longer (see `retry_transient/2`).

  ## Bringing your own Finch pool

  Pass `finch: MyApp.Finch` (a name you started and configured yourself)
  to route requests through your own pool. Req 0.7 forbids pool options
  alongside a pool name, so that also makes transport security *your*
  responsibility: combining `:finch` with `:cert_fingerprints`,
  `verify_ssl: false`, or `:connect_timeout` raises rather than silently
  dropping them.
  """
  @spec new(keyword()) :: client()
  def new(opts \\ []) do
    base_url = opts[:base_url] || Application.get_env(:unifi_api, :base_url)
    api_key = opts[:api_key] || Application.get_env(:unifi_api, :api_key)

    # Production-safe HTTP defaults; streams override `retry: false`
    # per-page (see `stream/3`/`stream_v1/3`/`stream_paged/3`).
    receive_timeout = Keyword.get(opts, :receive_timeout, 30_000)
    pool_timeout = Keyword.get(opts, :pool_timeout, 5_000)
    max_retries = Keyword.get(opts, :max_retries, 1)

    Req.new(
      base_url: base_url,
      redirect: false,
      receive_timeout: receive_timeout,
      finch: [pool_timeout: pool_timeout] ++ finch_pool_opts(opts),
      retry: if(max_retries > 0, do: &retry_transient/2, else: false),
      max_retries: max_retries
    )
    |> put_api_key(api_key)
    |> put_prefixes(opts)
  end

  # The API key is injected by a request step closing over it instead of
  # living in `:headers` (CWE-522 / CWE-209). Req's `Inspect` implementation
  # redacts `authorization` and nothing else, so an `x-api-key` header is
  # rendered verbatim — and this struct is argument one of every public
  # function in the library, so it lands in every stack frame, `dbg/1`,
  # crash log, and error-tracker breadcrumb. A closure inspects as
  # `#Function<...>`; its captured environment is never rendered.
  #
  # Deliberately *not* `:persistent_term` (which is how `UnifiApi.Auth.Session`
  # holds its rotating cookie/CSRF): the key never mutates, clients are built
  # ad hoc by callers, and a per-client entry would leak for the life of the
  # VM while making every subsequent `put/2` scan more live data.
  defp put_api_key(req, nil), do: req

  defp put_api_key(req, api_key) when is_binary(api_key) do
    Req.Request.append_request_steps(req,
      unifi_api_key: fn request ->
        Req.Request.put_new_header(request, "x-api-key", api_key)
      end
    )
  end

  # Replicates Req's `retry: :safe_transient` classification, but bounds the
  # delay a hostile or misconfigured controller can impose.
  #
  # Req honours `Retry-After` verbatim, so `Retry-After: 3600` parks the
  # calling process for an hour *inside* what reads as a bounded `Req.get/2`
  # — `:receive_timeout` does not cover the retry sleep. Both this path and
  # the `RateLimitError` path route through `parse_retry_after/1`, so the
  # 1..#{@retry_after_ceiling_seconds}s bound is applied in exactly one
  # place. `Req.Response.get_retry_after/1` is deliberately *not* used: it
  # raises `ArgumentError` on a value it cannot parse, and a controller is
  # free to send `Retry-After: soon`.
  #
  # `:retry_delay` cannot express this. Setting it makes Req ignore
  # `Retry-After` outright (`Req.Steps.get_retry_delay/3`) and the callback
  # only receives an attempt count, so it can never see the header value.
  # A 2-arity `:retry` returning `{:delay, ms}` is the only shape that can
  # both honour and bound it — and it requires `:retry_delay` to stay unset,
  # which is why `new/1` does not set it.
  @doc false
  @spec retry_transient(Req.Request.t(), Req.Response.t() | Exception.t()) ::
          boolean() | {:delay, pos_integer()}
  def retry_transient(%Req.Request{method: method}, _response_or_exception)
      when method not in [:get, :head],
      do: false

  def retry_transient(_request, %Req.Response{status: status} = response)
      when status in [429, 503] do
    # An unparseable header is treated as *absent* rather than as the 60s
    # default `parse_retry_after/1` uses for the `RateLimitError` path.
    # Otherwise `Retry-After: soon` would be a better attack than sending no
    # header at all: a measured 60s in-band sleep versus Req's own ~0.9s
    # exponential backoff.
    case parsed_retry_after(response) do
      {:ok, seconds} -> {:delay, seconds * 1_000}
      :error -> true
    end
  end

  def retry_transient(_request, %Req.Response{status: status})
      when status in [408, 500, 502, 504],
      do: true

  def retry_transient(_request, %Req.Response{}), do: false

  def retry_transient(_request, %Req.TransportError{reason: reason})
      when reason in [:timeout, :econnrefused, :closed],
      do: true

  def retry_transient(_request, %Req.HTTPError{protocol: :http2, reason: reason})
      when reason in [:unprocessed, :pool_not_available],
      do: true

  def retry_transient(_request, _other), do: false

  # Either the consumer owns the Finch pool or this client does. Req 0.7
  # makes that an either/or: `Req.Finch.finch_name_options/1` raises when
  # pool options are set alongside `finch: [name: _]`. `:pool_timeout` is a
  # *request* option (`@finch_request_options`), so it is split out before
  # the pool key is hashed and is legal in both branches.
  defp finch_pool_opts(opts) do
    case Keyword.get(opts, :finch) do
      nil ->
        # Always non-empty: the connect timeout is unconditional, so this
        # client always owns a configured pool rather than falling back to
        # Req's shared default one.
        [conn_opts: [transport_opts: transport_opts(opts)]]

      name when is_atom(name) ->
        guard_consumer_pool!(opts, name)
        [name: name]

      other ->
        raise ArgumentError,
              "expected :finch to be a Finch pool name (atom), got: #{inspect(other)}"
    end
  end

  # Silently discarding transport security would be a footgun, so say so.
  defp guard_consumer_pool!(opts, name) do
    dropped =
      Keyword.keys(tls_transport_opts(opts)) ++
        Keyword.keys(Keyword.take(opts, [:connect_timeout]))

    if dropped != [] do
      raise ArgumentError,
            "cannot combine finch: #{inspect(name)} with transport options " <>
              "#{inspect(Enum.uniq(dropped))} — Req 0.7 forbids pool options alongside a " <>
              "pool name, so they would be silently dropped. Configure them on the pool " <>
              "you start instead: {Finch, name: #{inspect(name)}, " <>
              "pools: %{default: [conn_opts: [transport_opts: [...]]]}}"
    end
  end

  # `timeout:` inside `:transport_opts` is exactly where Req itself lands
  # `connect_options: [timeout: _]` (`Req.Finch.pool_options/1` merges it
  # into the transport opts), so a client-owned pool spells it the same way.
  defp transport_opts(opts) do
    tls_transport_opts(opts) ++ [timeout: connect_timeout(opts)]
  end

  # `nil` from either source means "unset", not "zero". An explicit
  # `config :unifi_api, connect_timeout: nil` must not produce
  # `timeout: nil`, which `:ssl` would reject at connect time.
  @default_connect_timeout 5_000

  defp connect_timeout(opts) do
    opts[:connect_timeout] || Application.get_env(:unifi_api, :connect_timeout) ||
      @default_connect_timeout
  end

  defp tls_transport_opts(opts) do
    fingerprints =
      opts[:cert_fingerprints] ||
        Application.get_env(:unifi_api, :cert_fingerprints, [])

    # Secure by default (CWE-295 / OWASP A02). Callers with self-signed
    # UDM controllers must opt out explicitly via `verify_ssl: false` or
    # the `UNIFI_INSECURE_TLS=1` env var (see `config/runtime.exs`), or
    # pin the leaf cert with `:cert_fingerprints`.
    # `nil` from app env means "unset" and must fall through to the secure
    # default — treating it as falsy would silently downgrade to
    # `verify: :verify_none`.
    verify_ssl =
      case Keyword.fetch(opts, :verify_ssl) do
        {:ok, value} when is_boolean(value) -> value
        _ -> Application.get_env(:unifi_api, :verify_ssl) != false
      end

    cond do
      fingerprints != [] ->
        fingerprint_pinning_opts(opts[:base_url], fingerprints)

      verify_ssl ->
        []

      true ->
        [verify: :verify_none]
    end
  end

  # Certificate pinning. Two things to know, both established by driving a
  # real TLS handshake against a self-signed server (the plug adapter used
  # by the test suite never reaches `:ssl`, which is how the two bugs below
  # shipped in the first place):
  #
  #   1. The pinned fingerprint *is* the trust anchor, so the OS trust store
  #      is deliberately not passed. `verify: :verify_peer` still requires
  #      *a* CA source — `:ssl` rejects the combination outright with
  #      `{:options, :incompatible, ...}` when both `:cacerts` and
  #      `:cacertfile` are absent — so an empty list is supplied. Every
  #      certificate then arrives as `{:bad_cert, :unknown_ca}` or
  #      `{:bad_cert, :selfsigned_peer}`, which is precisely the branch the
  #      pin check owns.
  #
  #      This is also the fix for a CRITICAL per-request cost: Req derives
  #      the Finch pool name by hashing the pool options on *every* request
  #      (`Req.Finch.pool_name/1`). With `cacerts: :public_key.cacerts_get()`
  #      in there that was 476 KB serialized and ~2.4ms of CPU per request;
  #      measured at 364 bytes and ~2µs after this change.
  #
  #   2. No `:server_name` / SNI option is set here. `:server_name` is not
  #      an `:ssl` option at all: `:ssl` forwarded it to `gen_tcp:connect/4`,
  #      which raised `:badarg`, so *every* pinned connection failed before
  #      it could send a byte. Mint already sets `server_name_indication`
  #      from the connection hostname (`Mint.Core.Transport.SSL`), so the
  #      correct fix is to set nothing and let Mint do it. Hostname
  #      verification is enforced inside the verify fun instead, because a
  #      custom `:verify_fun` replaces OTP's own hostname check.
  defp fingerprint_pinning_opts(base_url, fingerprints) do
    decoded = Enum.map(fingerprints, &decode_fingerprint!/1)
    host = server_name_from_base_url(base_url)

    [
      verify: :verify_peer,
      cacerts: [],
      verify_fun: {build_fingerprint_verify_fun(decoded, host), :unpinned}
    ]
  end

  defp server_name_from_base_url(nil), do: nil

  defp server_name_from_base_url(base_url) when is_binary(base_url) do
    case URI.parse(base_url) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> nil
    end
  end

  # The verify fun is the whole of the pinning guarantee, so it fails
  # closed: there is no path to a successful handshake in which no
  # presented certificate matched a pinned fingerprint.
  #
  # The shape is forced by how OTP reports a chain it cannot anchor, which
  # was measured against a live `:ssl` server rather than assumed:
  #
  #   * A self-signed controller certificate (the UniFi default) is
  #     reported once as `{:bad_cert, :selfsigned_peer}` and OTP then
  #     considers validation finished — `:valid_peer` is *never* called for
  #     it. The previous implementation returned `{:valid, state}` for that
  #     reason unconditionally and only checked the fingerprint in the
  #     `:valid` / `:valid_peer` clauses, so the pin was never consulted at
  #     all: any self-signed certificate was accepted. That is a complete
  #     bypass of the advertised guarantee, so the check moved into this
  #     clause.
  #
  #   * A leaf whose issuer is simply unknown is *also* reported only once,
  #     as `{:bad_cert, :unknown_ca}`, with no `:valid_peer` to follow.
  #     Deferring the decision to a later callback therefore cannot be made
  #     safe, which is why every `:bad_cert` clause decides here and now.
  #
  #   * When a full chain is presented, `{:bad_cert, :unknown_ca}` carries
  #     the *anchor*, and `:valid_peer` follows for the leaf. Pinning the
  #     anchor is honoured (`state` carries `:pinned` forward) and the
  #     leaf's hostname is then verified, because trust inherited from a
  #     pinned CA covers any name that CA signs. Pinning a *leaf* that sits
  #     behind an unknown CA is rejected — pin the certificate the
  #     controller cannot prove, which is what `@doc` for `:cert_fingerprints`
  #     tells operators to do.
  #
  # A pinned certificate is not additionally hostname-checked: a SHA-256
  # pin names one exact certificate and is strictly stronger than a name
  # match, and UniFi controllers are routinely addressed by IP with a
  # certificate whose CN/SAN does not cover it.
  defp build_fingerprint_verify_fun(allowed, host) do
    fn
      cert, {:bad_cert, reason}, _state when reason in @weak_bad_cert_reasons ->
        if pinned?(cert, allowed),
          do: {:valid, :pinned},
          else: {:fail, {:bad_cert, reason}}

      _cert, {:bad_cert, reason}, _state ->
        {:fail, {:bad_cert, reason}}

      _cert, {:extension, _ext}, state ->
        {:unknown, state}

      cert, valid, state when valid in [:valid, :valid_peer] ->
        cond do
          pinned?(cert, allowed) -> {:valid, :pinned}
          state != :pinned -> {:fail, :fingerprint_mismatch}
          hostname_match?(cert, host) -> {:valid, :pinned}
          true -> {:fail, :hostname_check_failed}
        end
    end
  end

  # `:crypto.hash_equals/2` is OTP's constant-time comparison for
  # same-size binaries; both sides here are 32-byte SHA-256 digests
  # (`decode_fingerprint!/1` guarantees it). An attacker observing
  # handshake timing learns only how many fingerprints are pinned, not
  # which one matched (CWE-208).
  defp pinned?(otp_cert, allowed) do
    fp = :crypto.hash(:sha256, :public_key.pkix_encode(:OTPCertificate, otp_cert, :otp))
    Enum.any?(allowed, &:crypto.hash_equals(&1, fp))
  end

  # A custom `:verify_fun` replaces OTP's own hostname check, so it has to
  # be done here. `:base_url` may be an IP literal, which `pkix_verify_hostname/2`
  # matches under `:ip` rather than `:dns_id`.
  defp hostname_match?(_cert, nil), do: false

  defp hostname_match?(otp_cert, host) do
    charlist = String.to_charlist(host)

    :public_key.pkix_verify_hostname(otp_cert, dns_id: charlist) or
      :public_key.pkix_verify_hostname(otp_cert, ip: charlist)
  end

  @doc """
  Decodes a cert fingerprint string into 32 raw SHA-256 bytes.

  Accepts plain lowercase or uppercase hex, optionally prefixed with
  `"sha256:"` and/or separated by colons (the `ssh-keygen` format:

      iex> UnifiApi.Client.decode_fingerprint!("AB:" |> String.duplicate(31) <> "AB")
      <<0xAB::256>>

  Raises `ArgumentError` if the input is not exactly 64 hex characters
  after stripping the optional `"sha256:"` prefix and colons.

  Will be made `defp` in v0.5.0 once a higher-level `cert_fingerprints_from_host/1`
  helper covers the only in-tree caller. Until then it remains public so
  operators can build their own fingerprint stores from `ssh-keyscan`
  output (the audit flagged the prior `@doc false` + public `def` as a
  doc/code mismatch — now documented as public).
  """
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
  Returns one of the four API path prefixes for `client`.

  Prefixes are resolved once by `new/1` and stashed on the request via
  `Req.Request.put_private/3`, so two clients pointed at controllers of
  different flavours coexist in one VM. Before v0.4.0 they lived in global
  `Application` env, which made that impossible and meant any consumer
  calling `Application.put_env/3` at runtime raced every in-flight request.

  `api` is one of:

    * `:network` — integration API, default `"/proxy/network/integration"`.
    * `:protect` — integration API, default `"/proxy/protect/integration"`.
    * `:network_v1` — legacy `/api/s/{site}/...` and `/v2/api/site/{site}/...`
      endpoints (events, alarms, IDS, anomalies, historical clients, DPI,
      topology, ...) that Ubiquiti has not exposed under `x-api-key`. These
      need cookie + CSRF auth via `UnifiApi.Auth.Cookie`. Default
      `"/proxy/network"`.
    * `:protect_v1` — the cookie + CSRF-authed `/proxy/protect/api/events`
      log that predates the integration API. Default `"/proxy/protect"`.

  A client not built by `new/1` (a hand-rolled `Req.new/1`, as the test
  suite uses) falls back to `Application` env and then to the `:udm`
  defaults, so both styles of construction keep working.
  """
  @spec prefix(client(), api()) :: String.t()
  def prefix(%Req.Request{} = client, api) when api in @apis do
    case Req.Request.get_private(client, :unifi_api_prefixes) do
      %{^api => prefix} -> prefix
      _ -> resolved_prefixes([])[api]
    end
  end

  @doc """
  Returns the Network integration-API path prefix for `client`.
  """
  @spec network_prefix(client()) :: String.t()
  def network_prefix(client), do: prefix(client, :network)

  @doc """
  Returns the Protect integration-API path prefix for `client`.
  """
  @spec protect_prefix(client()) :: String.t()
  def protect_prefix(client), do: prefix(client, :protect)

  @doc """
  Returns the legacy v1 Network API path prefix for `client`.
  """
  @spec v1_prefix(client()) :: String.t()
  def v1_prefix(client), do: prefix(client, :network_v1)

  @doc """
  Returns the legacy v1 Protect API path prefix for `client`.
  """
  @spec protect_v1_prefix(client()) :: String.t()
  def protect_v1_prefix(client), do: prefix(client, :protect_v1)

  @doc """
  Returns the controller style this client was built for.

  `:udm` unless `new/1` was given `style: :cloud_key`.
  """
  @spec style(client()) :: style()
  def style(%Req.Request{} = client) do
    case Req.Request.get_private(client, :unifi_api_prefixes) do
      %{style: style} -> style
      _ -> @default_style
    end
  end

  defp put_prefixes(req, opts) do
    Req.Request.put_private(req, :unifi_api_prefixes, resolved_prefixes(opts))
  end

  # Resolution order, highest first:
  #
  #   1. an explicit per-prefix `new/1` option (`network_path:` etc.)
  #   2. the preset for an explicitly supplied `:style`
  #   3. the legacy `Application` env key
  #   4. the `:udm` preset
  #
  # `:style` outranks `Application` env deliberately: naming a style is a
  # statement about the controller in front of you, and it must not be
  # silently overridden by a global config left over from a different
  # controller. The env tier survives so existing configs keep working, and
  # it is precisely the tier that cannot express two flavours at once.
  defp resolved_prefixes(opts) do
    {style, style_given?} =
      case Keyword.fetch(opts, :style) do
        {:ok, style} -> {style, true}
        :error -> {@default_style, false}
      end

    preset =
      Map.get(@presets, style) ||
        raise ArgumentError,
              "expected :style to be one of #{inspect(Map.keys(@presets))}, " <>
                "got: #{inspect(style)}"

    Enum.reduce(@apis, %{style: style}, fn api, acc ->
      {opt_key, env_key} = @prefix_keys[api]

      value =
        case Keyword.fetch(opts, opt_key) do
          {:ok, explicit} -> explicit
          :error when style_given? -> preset[api]
          :error -> Application.get_env(:unifi_api, env_key) || preset[api]
        end

      Map.put(acc, api, value)
    end)
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
    req_opts = maybe_raw_opt(opts)

    client
    |> Req.get(Keyword.merge([url: path, params: params], req_opts))
    |> handle_response()
  end

  # `:raw` forwards `decode_body: false` (skips JSON decoding) on callers
  # that want the raw response body — heavy endpoints (events, system
  # log, NVR, cameras) so callers can stream/stream-parse large JSON
  # payloads without materialising the whole decoded map.
  defp maybe_raw_opt(opts) do
    if Keyword.get(opts, :raw, false),
      do: [decode_body: false],
      else: []
  end

  @doc """
  Performs a GET request against a legacy v1 endpoint and unwraps the
  `%{"meta" => %{"rc" => "ok"}, "data" => [...]}` envelope.

  Used by `UnifiApi.Network.Events`, `Alarms`, `ClientsLive`, etc. — all
  the endpoints that require cookie + CSRF auth via `UnifiApi.Auth.Cookie`.

  Returns:

    * `{:ok, data}` when `meta.rc == "ok"` (or no envelope is present).
    * `{:error, %UnifiApi.ApiError{code: code}}` when the controller returns
      `meta.rc == "error"` (e.g. `code == "api.err.LoginRequired"`). Note the
      HTTP status is normally `200` in this case — the failure lives in the
      body. Before v0.4.0 this was `{:error, {:unifi_error, msg}}`.
    * `{:error, error}` for transport / non-2xx responses, same as `get/3`.

  ## Options

  Same as `get/3`. The `:params` option is the most useful here:

      Client.get_v1(client, "/proxy/network/api/s/default/stat/event",
        params: [_limit: 100, within: 24])
  """
  @spec get_v1(client(), String.t(), keyword()) :: response()
  def get_v1(client, path, opts \\ []) do
    raw = Keyword.get(opts, :raw, false)

    # When `:raw` is set, bypass JSON decoding — `get_v1/3` returns the
    # raw `body` binary verbatim, since the `%{"meta" => "data"}` envelope
    # unwrap only makes sense on a decoded JSON body. The fallback
    # `unwrap_v1/1` catch-all `defp unwrap_v1(other), do: {:ok, other}`
    # will return the binary unchanged.
    result =
      if raw do
        case Req.get(client, url: path, params: build_params(opts), decode_body: false) do
          {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
            {:ok, body}

          {:ok, %Req.Response{} = resp} ->
            {:error, error_from_response(resp)}

          {:error, reason} ->
            {:error, UnifiApi.Error.from_transport(reason)}
        end
      else
        get(client, path, opts)
      end

    with {:ok, body} <- result, do: unwrap_v1(body)
  end

  defp unwrap_v1(%{"meta" => %{"rc" => "ok"}, "data" => data}), do: {:ok, data}

  defp unwrap_v1(%{"meta" => %{"rc" => "error"} = meta}) do
    {:error,
     %UnifiApi.ApiError{
       status: 200,
       code: meta["msg"] || "unknown",
       body_preview: nil
     }}
  end

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
        {:error, UnifiApi.Error.from_transport(reason)}
    end
  end

  @doc """
  Performs a GET request returning the raw `Req.Response.t()` struct.

  Used by callers that need the full response (status, headers, body)
  rather than the body-only / unwrapped-shape that `get/3` and
  `get_raw/3` produce. Routing through this entry point (rather than
  calling `Req.get/2` directly) keeps future Client-level hardening
  (redaction, retry policy, telemetry) uniform across all HTTP in the
  lib.

  Returns:

    * `{:ok, %Req.Response{}}` for any non-error HTTP transport
      (2xx, 3xx, 4xx, 5xx — the caller decides what to do with the
      status code).
    * `{:error, reason}` for transport-layer failure (timeout, DNS,
      connection refused).

  Redirects are already disabled by `Client.new/1` (`redirect: false`),
  so 3xx responses are surfaced verbatim — this is what
  `UnifiApi.detect/1` and `UnifiApi.ping/1` rely on.
  """
  @spec raw_get(client(), String.t(), keyword()) ::
          {:ok, Req.Response.t()} | {:error, term()}
  def raw_get(client, path, opts \\ []) do
    params = build_params(opts)
    Req.get(client, url: path, params: params)
  end

  @doc """
  Creates a lazy stream that automatically paginates through results.

  Uses `Stream.resource/3` to fetch pages on demand. Each page requests
  up to `:limit` items (default 200, the API maximum). The stream halts
  when a page returns fewer items than the limit, when `:max_pages` /
  `:max_items` is reached, or (post-v0.4.0) after a single
  `RateLimitError` retry-after backoff retries the same page.

  ## Error contract (changed in v0.4.0 — breaking)

  By default, a mid-stream API error **no longer raises**. The stream
  halts and yields `{:error, reason, last_offset}` as its final element,
  where `last_offset` is the offset of the failed page (so a caller can
  resume from `last_offset` after backoff). Consumers using
  `Enum.to_list/1` receive `[item, ..., {:error, reason, last_offset}]`
  and should pattern-match the tail:

      case Client.stream(client, path) |> Enum.to_list() do
        items ++ [{:error, reason, offset}] -> {:error, reason, offset}
        items -> {:ok, items}
      end

  The one exception is `UnifiApi.RateLimitError`: the stream honours the
  controller's `Retry-After` header once, sleeps, and retries the same
  page. A second consecutive 429 (or any other error class) terminates
  the stream and yields the standard error tuple.

  Pass `raise_errors: true` to restore the v0.3 raise-on-error behaviour
  (raises `UnifiApi.StreamError`). The `StreamError` struct redacts
  host/path/body in `message/1` (CWE-209 / OWASP A09).

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression
    * `:max_pages` — halt after this many successful pages (default:
      unbounded — halts only on a short page or error).
    * `:max_items` — halt once this many items have been yielded; the
      final page is truncated to fit (default: unbounded).
    * `:raise_errors` — when `true`, raise `StreamError` on error instead
      of yielding an error tuple (default: `false`).

  ## Examples

      # Stream all items
      Client.stream(client, "/v1/sites/abc/devices")
      |> Enum.to_list()

      # Stream with filter, take first 10
      Client.stream(client, "/v1/sites/abc/clients", filter: "type.eq(WIRELESS)")
      |> Enum.take(10)

      # Bounded scan — at most 5 pages or 1000 items
      Client.stream(client, "/v1/sites/abc/clients",
        max_pages: 5,
        max_items: 1000
      ) |> Enum.to_list()

      # Count all wireless clients across pages
      Client.stream(client, "/v1/sites/abc/clients", filter: "type.eq(WIRELESS)")
      |> Enum.count()
  """
  @spec stream(client(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, path, opts \\ []) do
    page_size = opts[:limit] || 200
    base_opts = Keyword.take(opts, [:filter])
    raise_errors = Keyword.get(opts, :raise_errors, false)
    max_pages = opts[:max_pages]
    max_items = opts[:max_items]
    # Disable retry per-page: re-fetching after the default 15s backoff
    # risks duplicate/stale data on paginated reads. RateLimitError is
    # handled explicitly below (one retry-after backoff then yield).
    stream_client = Req.merge(client, retry: false)
    fetch = &get(stream_client, path, Keyword.merge(base_opts, limit: page_size, offset: &1))
    advance = fn offset -> offset + page_size end
    bounds = {page_size, max_pages, max_items, raise_errors, path}

    stream_resource({0, 0, 0, false}, fetch, advance, bounds)
  end

  @doc """
  Generic page-number paginator for v2 endpoints that don't fit
  `stream/3` or `stream_v1/3`.

  Takes a `fetch_page` function that receives the current cursor and
  returns `{:ok, list}` (the page of items) or `{:error, reason}`.
  Halts when a page returns fewer than `:limit` items.

  ## Error contract (changed in v0.4.0 — breaking)

  Like `stream/3`, a mid-stream error halts the stream and yields
  `{:error, reason, last_cursor}` as the final element by default. Pass
  `raise_errors: true` to raise `UnifiApi.StreamError` instead.

  ## Options

    * `:limit` — items per page (default 500). Used to detect the
      last page (a short page halts the stream).
    * `:start_at` — initial cursor value (default 0; for endpoints
      that page from 1 set `start_at: 1`).
    * `:increment` — how much to advance the cursor between pages.
      Use `1` for `pageNumber`-style paging, or set to `:limit` (the
      page size) for offset-style paging.
    * `:raise_errors` — when `true`, raise `StreamError` on error (default: `false`).

  **Retry**: `stream_paged/2` invokes the caller's `fetch_page` closure,
  so per-page retry is controlled by the client you close over. Pass a
  `retry: false` client (e.g. `Req.merge(client, retry: false)`) —
  re-issuing a paginated request after a 15s backoff risks
  duplicates/stale data.

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
    raise_errors = Keyword.get(opts, :raise_errors, false)
    max_pages = opts[:max_pages]
    max_items = opts[:max_items]

    advance = fn cursor -> cursor + increment end
    bounds = {page_size, max_pages, max_items, raise_errors, "stream_paged"}

    stream_resource({initial, 0, 0, false}, fetch_page, advance, bounds)
  end

  @doc """
  Like `stream/3` but for legacy v1 endpoints.

  Pages on `_start` / `_limit` (the v1 convention) rather than
  `offset` / `limit`, and unwraps the v1 response envelope via
  `get_v1/3`. Used by `UnifiApi.Network.Events.stream/3`,
  `Alarms.stream/3`, etc.

  ## Error contract (changed in v0.4.0 — breaking)

  Like `stream/3`, a mid-stream error halts the stream and yields
  `{:error, reason, last_start}` as the final element by default. Pass
  `raise_errors: true` to raise `UnifiApi.StreamError` instead.

  ## Options

    * `:limit` — items per page (default: 500, the typical v1 cap)
    * `:params` — additional query params merged on every request
      (e.g. `[within: 24]` to time-window the entire stream)
    * `:max_pages` — halt after this many successful pages (default: unbounded).
    * `:max_items` — halt once this many items have been yielded; the
      final page is truncated to fit (default: unbounded).
    * `:raise_errors` — when `true`, raise `StreamError` on error (default: `false`).
  """
  @spec stream_v1(client(), String.t(), keyword()) :: Enumerable.t()
  def stream_v1(client, path, opts \\ []) do
    page_size = opts[:limit] || 500
    base_params = Keyword.get(opts, :params, [])
    raise_errors = Keyword.get(opts, :raise_errors, false)
    stream_client = Req.merge(client, retry: false)

    fetch = fn start ->
      params = base_params ++ [_start: start, _limit: page_size]
      get_v1(stream_client, path, params: params)
    end

    advance = fn start -> start + page_size end
    bounds = {page_size, opts[:max_pages], opts[:max_items], raise_errors, path}

    stream_resource({0, 0, 0, false}, fetch, advance, bounds)
  end

  # Shared `Stream.resource` core for `stream/3`, `stream_v1/3`, and
  # `stream_paged/2`. State is `{cursor, pages_fetched, items_yielded,
  # retried_429?}`. `fetch` is a 1-arity fn `cursor -> result`; `advance`
  # is `cursor -> next_cursor` for the success branch.
  #
  # Caps (`:max_pages` / `:max_items`) and one-shot RateLimitError
  # retry-after backoff apply uniformly to all three stream variants.
  defp stream_resource(
         initial,
         fetch,
         advance,
         {page_size, max_pages, max_items, raise_errors, path}
       ) do
    Stream.resource(
      fn -> initial end,
      fn
        :halt ->
          {:halt, :done}

        {cursor, pages, items, retried?} ->
          cond do
            (max_pages != nil and pages >= max_pages) or
                (max_items != nil and items >= max_items) ->
              {:halt, :done}

            true ->
              case fetch.(cursor) do
                {:ok, page} when is_list(page) ->
                  pages_now = pages + 1

                  emit =
                    if max_items != nil do
                      remaining = max_items - items
                      if remaining <= 0, do: [], else: Enum.take(page, remaining)
                    else
                      page
                    end

                  items_now = items + length(emit)

                  halt? =
                    length(page) < page_size or
                      (max_pages != nil and pages_now >= max_pages) or
                      (max_items != nil and items_now >= max_items)

                  if halt?,
                    do: {emit, :halt},
                    else: {emit, {advance.(cursor), pages_now, items_now, retried?}}

                {:error, %UnifiApi.RateLimitError{retry_after: secs}} when not retried? ->
                  # Honour the controller's Retry-After header once, then
                  # retry the SAME page (no cursor advance). A second
                  # consecutive 429 falls through to the generic error
                  # branch below and yields `{:error, reason, cursor}`.
                  Process.sleep(secs * 1000)

                  {[], {cursor, pages, items, true}}

                {:error, reason} ->
                  handle_stream_error(raise_errors, reason, path, cursor)

                {:ok, non_list} ->
                  handle_stream_error(
                    raise_errors,
                    {:unexpected_response, non_list},
                    path,
                    cursor
                  )
              end
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

  # A transport failure never produced a response. Wrapping Req's exception
  # keeps the umbrella closed: before v0.4.0 a bare `%Req.TransportError{}`
  # leaked out here while callers up the stack expected a `%AuthError{}` or
  # a `{status, body}` tuple, so nobody could write an exhaustive `case`.
  defp handle_response({:error, reason}) do
    {:error, UnifiApi.Error.from_transport(reason)}
  end

  defp error_from_response(%Req.Response{status: 429, body: body} = resp) do
    %UnifiApi.RateLimitError{
      retry_after: parse_retry_after(Req.Response.get_header(resp, "retry-after")),
      status: 429,
      body_preview: scrub_body_preview(body)
    }
  end

  defp error_from_response(%Req.Response{status: 401, body: body}) do
    %UnifiApi.AuthError{
      status: 401,
      body_preview: scrub_body_preview(body),
      reason: :unauthorized
    }
  end

  defp error_from_response(%Req.Response{status: 403, body: body}) do
    %UnifiApi.AuthError{
      status: 403,
      body_preview: scrub_body_preview(body),
      reason: :forbidden
    }
  end

  # Every remaining non-2xx status. This used to be a bare `{status, body}`
  # tuple, which both leaked the raw body and could not be matched
  # exhaustively alongside the exception structs above.
  defp error_from_response(%Req.Response{status: status, body: body}) do
    %UnifiApi.ApiError{
      status: status,
      body_preview: scrub_body_preview(body)
    }
  end

  # Parses Retry-After (RFC 7231 §7.1.3): delay-seconds or a date. Always
  # clamped to 1..@retry_after_ceiling_seconds, so every caller gets a bounded
  # sleep for free. Falls back to @retry_after_default_seconds when the header
  # is missing or unusable — see `parsed_retry_after/1` for the callers that
  # need to tell those two cases apart.
  defp parse_retry_after(header) do
    case parsed_retry_after_header(header) do
      {:ok, seconds} -> seconds
      :error -> @retry_after_default_seconds
    end
  end

  defp parsed_retry_after(%Req.Response{} = response) do
    response
    |> Req.Response.get_header("retry-after")
    |> parsed_retry_after_header()
  end

  defp parsed_retry_after_header([value | _]) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} ->
        {:ok, clamp_retry_after(seconds)}

      _ ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _} -> {:ok, clamp_retry_after(DateTime.diff(dt, DateTime.utc_now()))}
          _ -> :error
        end
    end
  end

  defp parsed_retry_after_header(_absent), do: :error

  defp clamp_retry_after(seconds) when seconds <= 1, do: 1

  defp clamp_retry_after(seconds) when seconds >= @retry_after_ceiling_seconds,
    do: @retry_after_ceiling_seconds

  defp clamp_retry_after(seconds), do: seconds

  @preview_limit 128
  @preview_scan_bytes 512

  @doc """
  Scrubs a response body into a short, safe diagnostic preview.

  Used by `UnifiApi.AuthError` / `UnifiApi.RateLimitError` /
  `UnifiApi.StreamError` to avoid leaking raw bodies into logs or
  exception trackers (CWE-209 / OWASP A09). The returned binary is:

    * ≤ #{@preview_limit} characters (truncated with `…`),
    * URL-like patterns (`https?://...`) replaced with `[url]`,
    * host-like patterns (`foo.example.com`, IPv4 literals) replaced
      with `[host]`,
    * JSON-encoded when the body is a map/list.

  Returns `nil` for empty bodies.
  """
  @spec scrub_body_preview(term()) :: binary() | nil
  def scrub_body_preview(nil), do: nil
  def scrub_body_preview(""), do: nil

  def scrub_body_preview(body) when is_binary(body) do
    # Truncate *first*. Each redaction is a full-body regex pass, and this
    # runs on every 401/403/429 to produce at most #{@preview_limit}
    # characters: on an 888 KB body the scrub-then-truncate order cost
    # 33.5ms and ~2.6 MB of garbage for a 130-byte result. The scan window
    # is deliberately larger than the output because `[url]`/`[host]` can
    # be longer than the shortest thing they replace.
    body
    |> scan_window()
    |> redact_urls(~r/https?:\/\/[^\s"']+/)
    |> redact_hosts(
      ~r/\b[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?){1,}\b/i
    )
    |> redact_ipv4(~r/\b(?:\d{1,3}\.){3}\d{1,3}\b/)
    |> truncate(@preview_limit)
  end

  def scrub_body_preview(body) when is_map(body) or is_list(body) do
    body
    |> JSON.encode!()
    |> scrub_body_preview()
  rescue
    _ -> scrub_body_preview(inspect(body))
  end

  def scrub_body_preview(other), do: scrub_body_preview(inspect(other))

  defp scan_window(body) when byte_size(body) <= @preview_scan_bytes, do: body

  defp scan_window(body) do
    body |> binary_part(0, @preview_scan_bytes) |> trim_partial_codepoint(3)
  end

  # `binary_part/3` can cut a multi-byte codepoint in half, and the regex
  # passes need valid UTF-8. Drop up to three trailing bytes to close the
  # codepoint; give up after that so a body that is not UTF-8 at all
  # (a binary blob) behaves exactly as it did before, rather than being
  # whittled away.
  defp trim_partial_codepoint(bin, 0), do: bin

  defp trim_partial_codepoint(bin, attempts) do
    if String.valid?(bin) do
      bin
    else
      size = byte_size(bin) - 1
      <<head::binary-size(^size), _::binary>> = bin
      trim_partial_codepoint(head, attempts - 1)
    end
  end

  defp redact_urls(str, regex), do: String.replace(str, regex, "[url]")
  defp redact_hosts(str, regex), do: String.replace(str, regex, "[host]")
  defp redact_ipv4(str, regex), do: String.replace(str, regex, "[host]")

  defp truncate(str, max) when is_binary(str) do
    if String.length(str) <= max do
      str
    else
      String.slice(str, 0, max - 1) <> "…"
    end
  end

  defp handle_stream_error(true = _raise, reason, path, _cursor) do
    raise build_stream_error(reason, path)
  end

  defp handle_stream_error(false = _raise, reason, path, cursor) do
    # Yield the error tuple as the final stream element and halt. `cursor` is
    # the offset/start/page of the failed request, so callers resume from
    # `cursor` after backoff.
    {[{:error, build_stream_error(reason, path), cursor}], :halt}
  end

  @doc false
  @spec build_stream_error(term(), String.t()) :: UnifiApi.StreamError.t()
  def build_stream_error(reason, path) when is_binary(path) do
    {kind, status} = stream_kind_status(reason)

    %UnifiApi.StreamError{
      kind: kind,
      status: status,
      reason: scrub_stream_reason(reason),
      path: path,
      host: stream_host(path)
    }
  end

  # This struct is *returned to the caller* as the stream's final element, so
  # it reaches logs, `inspect/1`, and exception trackers even though
  # `message/1` redacts. Every umbrella member already carries only a scrubbed
  # `body_preview`, but `{:unexpected_response, body}` used to retain the
  # entire decoded response body verbatim — a raw-body leak by the back door
  # (CWE-209 / OWASP A09). Anything not already in the umbrella is funnelled
  # through it.
  defp scrub_stream_reason({:error, reason}), do: scrub_stream_reason(reason)

  defp scrub_stream_reason({tag, body}) when tag in [:unexpected_response, :unexpected] do
    {tag, scrub_body_preview(body)}
  end

  defp scrub_stream_reason(%UnifiApi.AuthError{} = error), do: error
  defp scrub_stream_reason(%UnifiApi.RateLimitError{} = error), do: error
  defp scrub_stream_reason(%UnifiApi.ApiError{} = error), do: error
  defp scrub_stream_reason(%UnifiApi.TransportError{} = error), do: error
  defp scrub_stream_reason(reason), do: UnifiApi.Error.from_transport(reason)

  # `reason` reaches here either bare or wrapped in an `{:error, _}` tuple
  # depending on which stream variant produced it, so both are matched.
  defp stream_kind_status({:error, reason}), do: stream_kind_status(reason)
  defp stream_kind_status(%UnifiApi.AuthError{status: s}), do: {:auth, s}
  defp stream_kind_status(%UnifiApi.RateLimitError{status: s}), do: {:rate_limit, s}
  defp stream_kind_status(%UnifiApi.ApiError{status: s}) when is_integer(s), do: {:api, s}
  defp stream_kind_status(%UnifiApi.ApiError{}), do: {:api, :unknown}
  defp stream_kind_status(%UnifiApi.TransportError{}), do: {:transport, :unknown}
  defp stream_kind_status({:unexpected_response, _}), do: {:unexpected, :unknown}
  defp stream_kind_status({:unexpected, _non_list}), do: {:unexpected, :unknown}
  defp stream_kind_status(_), do: {:unknown, :unknown}

  defp stream_host(path) when is_binary(path) do
    case Regex.run(~r{^https?://([^/?#]+)}, path) do
      [_, host] -> host
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
