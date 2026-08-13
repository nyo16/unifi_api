defmodule UnifiApi.ClientTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Client

  defp test_client(plug) do
    Req.new(
      base_url: "http://localhost",
      headers: [{"x-api-key", "test-key"}],
      plug: plug,
      retry: false
    )
  end

  # Req 0.7 carries TLS settings in `finch: [conn_opts: [transport_opts: _]]`
  # rather than the old top-level `:connect_options`. Extract through one
  # helper so a future Req option-shape change touches a single place.
  defp tls_opts(%Req.Request{} = client) do
    get_in(client.options, [:finch, :conn_opts, :transport_opts]) || []
  end

  describe "new/1" do
    test "returns a Req.Request struct" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "abc")
      assert %Req.Request{} = client
    end

    test "sends x-api-key header" do
      client =
        Client.new(base_url: "http://localhost", api_key: "secret123")
        |> Req.merge(
          plug: fn conn ->
            [key] = Plug.Conn.get_req_header(conn, "x-api-key")
            Req.Test.json(conn, %{"key" => key})
          end
        )

      assert {:ok, %{"key" => "secret123"}} = Client.get(client, "/v1/info")
    end

    test "sets base_url without path prefix" do
      client =
        Client.new(base_url: "http://localhost", api_key: "k")
        |> Req.merge(
          plug: fn conn ->
            Req.Test.json(conn, %{"path" => conn.request_path})
          end
        )

      assert {:ok, %{"path" => "/v1/info"}} = Client.get(client, "/v1/info")
    end

    test "respects verify_ssl: true" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "abc", verify_ssl: true)
      assert %Req.Request{} = client
      # When verify_ssl is true, no TLS overrides are set (Req/mint verify
      # peer + hostname by default — no verify_none override). The connect
      # timeout is always present; see "connect timeout" below.
      assert tls_opts(client) == [timeout: 5_000]
    end

    test "defaults to verify peer (no TLS overrides, secure by default)" do
      # Reset app env to the secure default to avoid leakage from other tests.
      prev = Application.get_env(:unifi_api, :verify_ssl)
      Application.put_env(:unifi_api, :verify_ssl, true)
      on_exit(fn -> Application.put_env(:unifi_api, :verify_ssl, prev) end)

      client = Client.new(base_url: "https://10.0.0.1", api_key: "abc")
      assert tls_opts(client) == [timeout: 5_000]
    end

    test "explicit verify_ssl: false opts out with verify_none" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "abc", verify_ssl: false)
      assert tls_opts(client) == [verify: :verify_none, timeout: 5_000]
    end

    test "cert_fingerprints overrides verify_ssl" do
      fp = String.duplicate("cd", 32)

      client =
        Client.new(
          base_url: "https://10.0.0.1",
          api_key: "k",
          verify_ssl: false,
          cert_fingerprints: [fp]
        )

      tls = tls_opts(client)
      assert tls[:verify] == :verify_peer
    end

    test "cert_fingerprints raises on invalid input" do
      assert_raise ArgumentError, ~r/invalid SHA-256 cert fingerprint/, fn ->
        Client.new(base_url: "https://10.0.0.1", api_key: "k", cert_fingerprints: ["nope"])
      end
    end
  end

  describe "path prefixes on the client" do
    test "defaults to the UDM prefixes" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "k")

      assert Client.style(client) == :udm
      assert Client.network_prefix(client) == "/proxy/network/integration"
      assert Client.protect_prefix(client) == "/proxy/protect/integration"
      assert Client.v1_prefix(client) == "/proxy/network"
      assert Client.protect_v1_prefix(client) == "/proxy/protect"
    end

    test "style: :cloud_key selects the Cloud Key prefixes" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "k", style: :cloud_key)

      assert Client.style(client) == :cloud_key
      assert Client.network_prefix(client) == "/integration"
      assert Client.protect_prefix(client) == "/integration"
      assert Client.v1_prefix(client) == ""
      assert Client.protect_v1_prefix(client) == "/protect"
    end

    test "a UDM and a Cloud Key client coexist in one VM" do
      # The headline fix: before v0.4.0 the prefixes lived in global
      # application config, so these two could not both be correct at the
      # same time, and any `Application.put_env/3` raced in-flight requests.
      udm = Client.new(base_url: "https://10.0.0.1", api_key: "k", style: :udm)
      cloud_key = Client.new(base_url: "https://10.0.0.2", api_key: "k", style: :cloud_key)

      assert Client.network_prefix(udm) == "/proxy/network/integration"
      assert Client.network_prefix(cloud_key) == "/integration"
    end

    test "an explicit style outranks the legacy application env" do
      prev = Application.get_env(:unifi_api, :network_path)
      Application.put_env(:unifi_api, :network_path, "/proxy/network/integration")
      on_exit(fn -> Application.put_env(:unifi_api, :network_path, prev) end)

      # Naming a style is a statement about the controller in front of you;
      # a global config left over from a different controller must not win.
      client = Client.new(base_url: "https://10.0.0.1", api_key: "k", style: :cloud_key)
      assert Client.network_prefix(client) == "/integration"
    end

    test "a per-prefix option outranks the style preset" do
      client =
        Client.new(
          base_url: "https://10.0.0.1",
          api_key: "k",
          style: :cloud_key,
          network_path: "/custom/network"
        )

      assert Client.network_prefix(client) == "/custom/network"
      # Untouched keys still follow the style.
      assert Client.v1_prefix(client) == ""
    end

    test "the legacy application env still applies when no style is given" do
      prev = Application.get_env(:unifi_api, :protect_v1_path)
      Application.put_env(:unifi_api, :protect_v1_path, "/legacy/protect")
      on_exit(fn -> restore_env(:protect_v1_path, prev) end)

      client = Client.new(base_url: "https://10.0.0.1", api_key: "k")
      assert Client.protect_v1_prefix(client) == "/legacy/protect"
    end

    test "a hand-built Req client falls back rather than crashing" do
      # The test suite (and any consumer wiring Req directly) builds clients
      # without `new/1`, so there is no private prefix map to read.
      client = Req.new(base_url: "http://localhost")

      assert Client.style(client) == :udm
      assert Client.network_prefix(client) == "/proxy/network/integration"
    end

    test "rejects an unknown style" do
      assert_raise ArgumentError, ~r/expected :style to be one of/, fn ->
        Client.new(base_url: "https://10.0.0.1", api_key: "k", style: :nonsense)
      end
    end

    defp restore_env(key, nil), do: Application.delete_env(:unifi_api, key)
    defp restore_env(key, value), do: Application.put_env(:unifi_api, key, value)
  end

  describe "credential handling (CWE-522 / CWE-209)" do
    test "inspect/1 of a client never renders the API key" do
      # Req's own `Inspect` implementation redacts `authorization` and
      # nothing else, so an `x-api-key` *header* is printed verbatim — and
      # this struct is argument one of every public function in the library,
      # so it reaches every stack frame, `dbg/1`, crash log, and error
      # tracker breadcrumb.
      client = Client.new(base_url: "https://10.0.0.1", api_key: "sekret-api-key")

      rendered = inspect(client, limit: :infinity, printable_limit: :infinity)

      refute rendered =~ "sekret-api-key"
    end

    test "the key is not reachable through headers, options, or private" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "sekret-api-key")

      assert Req.Request.get_header(client, "x-api-key") == []

      refute inspect(client.options, limit: :infinity) =~ "sekret-api-key"
      refute inspect(client.private, limit: :infinity) =~ "sekret-api-key"
    end

    test "the key still reaches the wire" do
      client =
        Client.new(base_url: "http://localhost", api_key: "sekret-api-key")
        |> Req.merge(
          plug: fn conn ->
            Req.Test.json(conn, %{"key" => Plug.Conn.get_req_header(conn, "x-api-key")})
          end
        )

      assert {:ok, %{"key" => ["sekret-api-key"]}} = Client.get(client, "/v1/info")
    end

    test "no api key means no header" do
      prev = Application.get_env(:unifi_api, :api_key)
      Application.delete_env(:unifi_api, :api_key)
      on_exit(fn -> Application.put_env(:unifi_api, :api_key, prev) end)

      client =
        Client.new(base_url: "http://localhost")
        |> Req.merge(
          plug: fn conn ->
            Req.Test.json(conn, %{"key" => Plug.Conn.get_req_header(conn, "x-api-key")})
          end
        )

      assert {:ok, %{"key" => []}} = Client.get(client, "/v1/info")
    end
  end

  describe "connect timeout" do
    test "defaults to 5s and lands where Req puts connect_options[:timeout]" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "k")
      assert tls_opts(client)[:timeout] == 5_000
    end

    test "is configurable" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "k", connect_timeout: 250)
      assert tls_opts(client)[:timeout] == 250
    end

    test "is configurable through application env" do
      prev = Application.get_env(:unifi_api, :connect_timeout)
      Application.put_env(:unifi_api, :connect_timeout, 750)
      on_exit(fn -> Application.put_env(:unifi_api, :connect_timeout, prev) end)

      client = Client.new(base_url: "https://10.0.0.1", api_key: "k")
      assert tls_opts(client)[:timeout] == 750
    end

    test "survives alongside pinning" do
      client =
        Client.new(
          base_url: "https://10.0.0.1",
          api_key: "k",
          connect_timeout: 1_234,
          cert_fingerprints: [String.duplicate("ab", 32)]
        )

      tls = tls_opts(client)
      assert tls[:timeout] == 1_234
      assert tls[:verify] == :verify_peer
    end
  end

  describe "consumer-owned Finch pool" do
    test "routes through the given pool name" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "k", finch: MyApp.Finch)

      assert client.options[:finch][:name] == MyApp.Finch
      # Req 0.7 raises if pool options accompany a name; `:pool_timeout` is a
      # *request* option and is therefore still legal.
      refute Keyword.has_key?(client.options[:finch], :conn_opts)
      assert client.options[:finch][:pool_timeout] == 5_000
    end

    test "refuses to silently drop transport security" do
      for conflicting <- [
            [cert_fingerprints: [String.duplicate("ab", 32)]],
            [verify_ssl: false],
            [connect_timeout: 100]
          ] do
        assert_raise ArgumentError, ~r/cannot combine finch:/, fn ->
          Client.new(
            [base_url: "https://10.0.0.1", api_key: "k", finch: MyApp.Finch] ++ conflicting
          )
        end
      end
    end

    test "rejects a non-atom pool" do
      assert_raise ArgumentError, ~r/expected :finch to be a Finch pool name/, fn ->
        Client.new(base_url: "https://10.0.0.1", api_key: "k", finch: [name: MyApp.Finch])
      end
    end
  end

  describe "retry_transient/2" do
    defp req(method), do: %Req.Request{method: method}

    defp resp(status, headers \\ []) do
      Enum.reduce(headers, %Req.Response{status: status}, fn {k, v}, acc ->
        Req.Response.put_header(acc, k, v)
      end)
    end

    test "clamps a server-controlled Retry-After to 300s" do
      # A `Retry-After: 3600` used to park the calling process for an hour
      # *inside* what reads as a bounded `Req.get/2` — `:receive_timeout`
      # does not cover the retry sleep.
      assert Client.retry_transient(req(:get), resp(429, [{"retry-after", "3600"}])) ==
               {:delay, 300_000}

      assert Client.retry_transient(req(:get), resp(503, [{"retry-after", "99999"}])) ==
               {:delay, 300_000}
    end

    test "honours a reasonable Retry-After verbatim" do
      assert Client.retry_transient(req(:get), resp(429, [{"retry-after", "5"}])) ==
               {:delay, 5_000}
    end

    test "falls back to Req's own backoff when Retry-After is absent" do
      assert Client.retry_transient(req(:get), resp(429)) == true
    end

    test "bounds nonsense Retry-After values instead of raising" do
      # `Req.Response.get_retry_after/1` raises `ArgumentError` on "soon", so
      # the library parses the header itself and clamps to 1..300s.
      assert Client.retry_transient(req(:get), resp(429, [{"retry-after", "-100"}])) ==
               {:delay, 1_000}
    end

    test "an unparseable Retry-After is treated as absent, not as 60s" do
      # Falling back to the 60s `RateLimitError` default here would make
      # `Retry-After: soon` a *better* attack than sending no header at all:
      # a measured 60s in-band sleep versus Req's own sub-second backoff.
      assert Client.retry_transient(req(:get), resp(429, [{"retry-after", "soon"}])) == true
      assert Client.retry_transient(req(:get), resp(429, [{"retry-after", ""}])) == true
      assert Client.retry_transient(req(:get), resp(429)) == true

      # The `RateLimitError` path keeps its documented 60s default.
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "soon")
          |> Plug.Conn.send_resp(429, "{}")
        end)

      assert {:error, %UnifiApi.RateLimitError{retry_after: 60}} = Client.get(client, "/v1/test")
    end

    test "matches :safe_transient's classification" do
      for status <- [408, 429, 500, 502, 503, 504] do
        assert Client.retry_transient(req(:get), resp(status)) != false,
               "expected #{status} to be retried"
      end

      for status <- [200, 400, 401, 403, 404, 409, 422] do
        assert Client.retry_transient(req(:get), resp(status)) == false,
               "expected #{status} not to be retried"
      end

      assert Client.retry_transient(req(:get), %Req.TransportError{reason: :timeout}) == true
      assert Client.retry_transient(req(:get), %Req.TransportError{reason: :nxdomain}) == false
    end

    test "only retries safe methods" do
      for method <- [:post, :put, :patch, :delete] do
        assert Client.retry_transient(req(method), resp(429, [{"retry-after", "1"}])) == false
      end

      assert Client.retry_transient(req(:head), resp(500)) == true
    end
  end

  describe "decode_fingerprint!/1" do
    test "decodes plain hex" do
      hex = String.duplicate("ab", 32)
      bin = String.duplicate(<<0xAB>>, 32)
      assert Client.decode_fingerprint!(hex) == bin
    end

    test "decodes uppercase hex" do
      hex = String.duplicate("AB", 32)
      bin = String.duplicate(<<0xAB>>, 32)
      assert Client.decode_fingerprint!(hex) == bin
    end

    test "strips sha256: prefix" do
      hex = String.duplicate("ab", 32)
      assert Client.decode_fingerprint!("sha256:" <> hex) == String.duplicate(<<0xAB>>, 32)
    end

    test "strips colons" do
      with_colons = "AB:" |> String.duplicate(31) |> Kernel.<>("AB")
      assert Client.decode_fingerprint!(with_colons) == String.duplicate(<<0xAB>>, 32)
    end

    test "accepts sha256: prefix with colons (ssh-keygen style)" do
      with_colons = "AB:" |> String.duplicate(31) |> Kernel.<>("AB")

      assert Client.decode_fingerprint!("sha256:" <> with_colons) ==
               String.duplicate(<<0xAB>>, 32)
    end

    test "rejects too-short input" do
      assert_raise ArgumentError, fn -> Client.decode_fingerprint!("abcd") end
    end

    test "rejects non-hex input" do
      assert_raise ArgumentError, fn -> Client.decode_fingerprint!(String.duplicate("zz", 32)) end
    end
  end

  describe "validate_id!/1 (P2-T3 boundary validation)" do
    test "accepts typical UniFi ids" do
      assert Client.validate_id!("default") == "default"
      assert Client.validate_id!("cam-1") == "cam-1"
      assert Client.validate_id!("65a3f4e2b1c4d0a3b2c1d0e3") == "65a3f4e2b1c4d0a3b2c1d0e3"
      assert Client.validate_id!(String.duplicate("a", 64)) == String.duplicate("a", 64)
    end

    test "rejects path-traversal sequences (CWE-22)" do
      for bad <- ["../etc", "..\\etc", "/etc/passwd", "a/b/c", "a;b", "a#b", "a?b"] do
        assert_raise ArgumentError, ~r/invalid resource id/, fn -> Client.validate_id!(bad) end
      end
    end

    test "rejects oversize ids (> 64 chars)" do
      assert_raise ArgumentError, fn -> Client.validate_id!(String.duplicate("a", 65)) end
    end

    test "rejects empty string" do
      assert_raise ArgumentError, fn -> Client.validate_id!("") end
    end

    test "rejects non-binary" do
      for bad <- [nil, 1, [], %{}] do
        assert_raise ArgumentError, fn -> Client.validate_id!(bad) end
      end
    end

    test "validate_ids!/1 validates every entry" do
      assert :ok = Client.validate_ids!(["a", "b", "c"])

      assert_raise ArgumentError, fn -> Client.validate_ids!(["a", "../bad"]) end
    end
  end

  describe "fingerprint pinning — option shape" do
    test "pins without dragging the OS trust store into the pool key" do
      client =
        Client.new(
          base_url: "https://controller.example.com:8443",
          api_key: "k",
          cert_fingerprints: [String.duplicate("ab", 32)]
        )

      tls = tls_opts(client)

      assert tls[:verify] == :verify_peer
      # The pin is the trust anchor, so no CA store is passed. `:ssl` still
      # requires *a* CA source under `:verify_peer`, hence the empty list.
      assert tls[:cacerts] == []
      assert {fun, :unpinned} = tls[:verify_fun]
      assert is_function(fun, 3)
    end

    test "does not set :server_name, which is not an :ssl option at all" do
      # Passing it made `:ssl` forward it to `gen_tcp:connect/4`, which
      # raised `:badarg` on every pinned connection. Mint sets
      # `server_name_indication` itself.
      client =
        Client.new(
          base_url: "https://controller.example.com:8443",
          api_key: "k",
          cert_fingerprints: [String.duplicate("ab", 32)]
        )

      tls = tls_opts(client)

      refute Keyword.has_key?(tls, :server_name)
      refute Keyword.has_key?(tls, :server_name_indication)
    end

    test "the pinned pool key stays small and stable" do
      client =
        Client.new(
          base_url: "https://udm.example",
          api_key: "k",
          cert_fingerprints: [String.duplicate("ab", 32)]
        )

      pool_opts = client.options[:finch][:conn_opts]

      # Req hashes the pool options on *every* request to derive the Finch
      # pool name (`Req.Finch.pool_name/1`). With the 162-certificate OS
      # trust store in there this term was ~476 KB and ~2.4ms of CPU per
      # request. Guard the regression with a generous ceiling.
      assert byte_size(:erlang.term_to_binary(pool_opts)) < 4_096

      # ... and the derived name must not change between requests, or every
      # request would start a new pool.
      assert Req.Finch.pool_name(pool_opts) == Req.Finch.pool_name(pool_opts)
    end

    test "accepts multiple fingerprints" do
      fps = [String.duplicate("ab", 32), String.duplicate("cd", 32), String.duplicate("ef", 32)]

      client =
        Client.new(base_url: "https://udm.example", api_key: "k", cert_fingerprints: fps)

      assert tls_opts(client)[:verify] == :verify_peer
    end
  end

  # These are the only tests in the suite that reach `:ssl`. Everything else
  # uses the `Req.Test` plug adapter, which short-circuits in `Req.Finch`
  # before transport options are ever validated — the blind spot that let
  # both a `:badarg` on every pinned connection and a total pin bypass ship.
  describe "fingerprint pinning — real TLS handshake" do
    alias UnifiApi.TestTLSServer, as: TLS

    defp pinned_get(port, fingerprints, host \\ "localhost") do
      Client.new(
        base_url: "https://#{host}:#{port}",
        api_key: "k",
        cert_fingerprints: fingerprints,
        max_retries: 0,
        connect_timeout: 2_000,
        # The fixture server completes the handshake and then says nothing,
        # so a *successful* handshake has to time out at the HTTP layer.
        # Keep that short: it is the pass condition for half these tests.
        receive_timeout: 300
      )
      |> Client.get("/")
    end

    test "self-signed controller certificate with the matching pin connects" do
      port = TLS.start("selfsigned.pem", "selfsigned.key.pem")

      # The server speaks TLS but no HTTP, so the request fails *after* a
      # successful handshake. Anything other than a TLS/handshake failure
      # proves the options were accepted and the pin matched.
      refute tls_rejected?(pinned_get(port, [TLS.fingerprint_hex("selfsigned.pem")]))
    end

    test "self-signed certificate with a non-matching pin is rejected" do
      port = TLS.start("selfsigned.pem", "selfsigned.key.pem")

      # Regression guard for a total bypass: the previous implementation
      # returned `{:valid, state}` for `{:bad_cert, :selfsigned_peer}` and
      # only checked the fingerprint in the `:valid_peer` clause, which OTP
      # never reaches for a self-signed peer. Every self-signed certificate
      # was accepted regardless of its fingerprint.
      assert tls_rejected?(pinned_get(port, [String.duplicate("ab", 32)]))
    end

    test "a leaf with an unknown issuer and a non-matching pin is rejected" do
      port = TLS.start("leaf.pem", "leaf.key.pem")

      assert tls_rejected?(pinned_get(port, [String.duplicate("ab", 32)]))
    end

    test "a leaf with an unknown issuer and the matching pin connects" do
      port = TLS.start("leaf.pem", "leaf.key.pem")

      refute tls_rejected?(pinned_get(port, [TLS.fingerprint_hex("leaf.pem")]))
    end

    test "pinning the CA anchor of a presented chain connects" do
      port = TLS.start("chain.pem", "leaf.key.pem")

      refute tls_rejected?(pinned_get(port, [TLS.fingerprint_hex("ca.pem")]))
    end

    test "trust inherited from a pinned CA still enforces the hostname" do
      port = TLS.start("chain.pem", "leaf.key.pem")

      # The fixture leaf is only valid for "localhost". A custom
      # `:verify_fun` replaces OTP's own hostname check, so the check has to
      # be re-implemented in the fun — this asserts it actually is.
      assert tls_rejected?(pinned_get(port, [TLS.fingerprint_hex("ca.pem")], "127.0.0.1"))
    end

    test "an unpinned certificate anywhere in the chain is rejected" do
      port = TLS.start("chain.pem", "leaf.key.pem")

      assert tls_rejected?(pinned_get(port, [String.duplicate("ab", 32)]))
    end

    test "a plain verify_ssl: false client reaches the socket" do
      port = TLS.start("selfsigned.pem", "selfsigned.key.pem")

      result =
        Client.new(
          base_url: "https://localhost:#{port}",
          api_key: "k",
          verify_ssl: false,
          max_retries: 0,
          connect_timeout: 2_000,
          receive_timeout: 300
        )
        |> Client.get("/")

      refute tls_rejected?(result)
    end

    # A TLS-layer refusal surfaces as a `Req.TransportError` whose reason is
    # a `:tls_alert` (or, for a rejected option set, an `ArgumentError`).
    # A handshake that succeeded fails later and differently.
    defp tls_rejected?({:error, %ArgumentError{}}), do: true
    defp tls_rejected?({:error, %UnifiApi.TransportError{reason: {:tls_alert, _}}}), do: true
    defp tls_rejected?({:error, %UnifiApi.TransportError{reason: {:options, _, _}}}), do: true
    defp tls_rejected?({:error, %UnifiApi.TransportError{reason: {:badarg, _}}}), do: true
    defp tls_rejected?(_other), do: false
  end

  describe "get/3" do
    test "returns {:ok, body} on 200" do
      client =
        test_client(fn conn ->
          assert conn.method == "GET"
          Req.Test.json(conn, %{"data" => "hello"})
        end)

      assert {:ok, %{"data" => "hello"}} = Client.get(client, "/v1/test")
    end

    test "returns %ApiError{} on 404" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(404, JSON.encode!(%{"error" => "not found"}))
        end)

      # The raw body is deliberately not retained; `body_preview` is scrubbed
      # and truncated by `scrub_body_preview/1`.
      assert {:error, %UnifiApi.ApiError{status: 404, code: nil, body_preview: preview}} =
               Client.get(client, "/v1/missing")

      assert preview =~ "not found"
    end

    test "returns %ApiError{} on 500" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "internal"}))
        end)

      assert {:error, %UnifiApi.ApiError{status: 500}} = Client.get(client, "/v1/broken")
    end

    test "passes offset, limit, and filter as query params" do
      client =
        test_client(fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          Req.Test.json(conn, params)
        end)

      assert {:ok, %{"offset" => "10", "limit" => "50", "filter" => "name.eq(foo)"}} =
               Client.get(client, "/v1/test", offset: 10, limit: 50, filter: "name.eq(foo)")
    end

    test "returns {:error, %AuthError{}} on 401" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(401, JSON.encode!(%{"error" => "unauthorized"}))
        end)

      assert {:error,
              %UnifiApi.AuthError{
                status: 401,
                reason: :unauthorized,
                body_preview: preview
              }} = Client.get(client, "/v1/test")

      assert is_binary(preview)
      assert preview =~ "unauthorized"
    end
  end

  describe "post/4" do
    test "sends JSON body and returns {:ok, body}" do
      client =
        test_client(fn conn ->
          assert conn.method == "POST"
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          body = JSON.decode!(raw)
          Req.Test.json(conn, %{"received" => body})
        end)

      assert {:ok, %{"received" => %{"name" => "test"}}} =
               Client.post(client, "/v1/resource", %{name: "test"})
    end

    test "returns %ApiError{} on a non-2xx response" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(422, JSON.encode!(%{"error" => "validation failed"}))
        end)

      assert {:error, %UnifiApi.ApiError{status: 422, body_preview: preview}} =
               Client.post(client, "/v1/resource", %{name: ""})

      assert preview =~ "validation failed"
    end
  end

  describe "put/4" do
    test "sends JSON body and returns {:ok, body}" do
      client =
        test_client(fn conn ->
          assert conn.method == "PUT"
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          body = JSON.decode!(raw)
          Req.Test.json(conn, %{"received" => body})
        end)

      assert {:ok, %{"received" => %{"name" => "updated"}}} =
               Client.put(client, "/v1/resource/1", %{name: "updated"})
    end
  end

  describe "patch/4" do
    test "sends JSON body and returns {:ok, body}" do
      client =
        test_client(fn conn ->
          assert conn.method == "PATCH"
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          body = JSON.decode!(raw)
          Req.Test.json(conn, %{"received" => body})
        end)

      assert {:ok, %{"received" => %{"field" => "value"}}} =
               Client.patch(client, "/v1/resource/1", %{field: "value"})
    end
  end

  describe "delete/3" do
    test "returns {:ok, body} on success" do
      client =
        test_client(fn conn ->
          assert conn.method == "DELETE"
          Req.Test.json(conn, %{"deleted" => true})
        end)

      assert {:ok, %{"deleted" => true}} = Client.delete(client, "/v1/resource/1")
    end
  end

  describe "get_raw/3" do
    test "returns raw binary body" do
      client =
        test_client(fn conn ->
          assert conn.method == "GET"

          conn
          |> Plug.Conn.put_resp_content_type("image/jpeg")
          |> Plug.Conn.send_resp(200, <<0xFF, 0xD8, 0xFF>>)
        end)

      assert {:ok, <<0xFF, 0xD8, 0xFF>>} = Client.get_raw(client, "/v1/snapshot")
    end

    test "returns {:error, %AuthError{reason: :forbidden}} on 403" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(403, JSON.encode!(%{"error" => "forbidden"}))
        end)

      assert {:error, %UnifiApi.AuthError{status: 403, reason: :forbidden}} =
               Client.get_raw(client, "/v1/snapshot")
    end

    test "passes highQuality param" do
      client =
        test_client(fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          Req.Test.json(conn, params)
        end)

      assert {:ok, %{"highQuality" => "true"}} =
               Client.get_raw(client, "/v1/snapshot", high_quality: true)
    end
  end

  describe "stream/3" do
    test "streams through multiple pages" do
      page_count = :counters.new(1, [:atomics])

      client =
        test_client(fn conn ->
          :counters.add(page_count, 1, 1)
          params = Plug.Conn.fetch_query_params(conn).query_params
          offset = String.to_integer(params["offset"] || "0")

          items =
            case offset do
              0 -> Enum.map(1..3, &%{"id" => &1})
              3 -> Enum.map(4..6, &%{"id" => &1})
              6 -> [%{"id" => 7}]
            end

          Req.Test.json(conn, items)
        end)

      result = Client.stream(client, "/v1/test", limit: 3) |> Enum.to_list()

      assert length(result) == 7
      assert List.first(result)["id"] == 1
      assert List.last(result)["id"] == 7
      assert :counters.get(page_count, 1) == 3
    end

    test "halts when first page is smaller than limit" do
      client =
        test_client(fn conn ->
          Req.Test.json(conn, [%{"id" => 1}, %{"id" => 2}])
        end)

      result = Client.stream(client, "/v1/test", limit: 5) |> Enum.to_list()
      assert length(result) == 2
    end

    test "handles empty first page" do
      client =
        test_client(fn conn ->
          Req.Test.json(conn, [])
        end)

      result = Client.stream(client, "/v1/test") |> Enum.to_list()
      assert result == []
    end

    test "is lazy — stops fetching after Enum.take" do
      page_count = :counters.new(1, [:atomics])

      client =
        test_client(fn conn ->
          :counters.add(page_count, 1, 1)
          items = Enum.map(1..3, &%{"id" => &1})
          Req.Test.json(conn, items)
        end)

      result = Client.stream(client, "/v1/test", limit: 3) |> Enum.take(2)

      assert length(result) == 2
      assert :counters.get(page_count, 1) == 1
    end

    test "passes filter to every page request" do
      client =
        test_client(fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["filter"] == "type.eq(WIRELESS)"

          items =
            if params["offset"] == "0",
              do: [%{"id" => 1}, %{"id" => 2}],
              else: [%{"id" => 3}]

          Req.Test.json(conn, items)
        end)

      result =
        Client.stream(client, "/v1/test", limit: 2, filter: "type.eq(WIRELESS)")
        |> Enum.to_list()

      assert length(result) == 3
    end

    test "yields {:error, StreamError, offset} on API error (v0.4 default)" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "boom"}))
        end)

      assert [{:error, %UnifiApi.StreamError{kind: :api, status: 500}, 0}] =
               Client.stream(client, "/v1/test") |> Enum.to_list()
    end

    test "yields error tuple mid-stream after a successful first page" do
      page_count = :counters.new(1, [:atomics])

      client =
        test_client(fn conn ->
          :counters.add(page_count, 1, 1)
          count = :counters.get(page_count, 1)

          if count == 1 do
            Req.Test.json(conn, Enum.map(1..3, &%{"id" => &1}))
          else
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "boom"}))
          end
        end)

      result = Client.stream(client, "/v1/test", limit: 3) |> Enum.to_list()

      assert [
               %{"id" => 1},
               %{"id" => 2},
               %{"id" => 3},
               {:error, %UnifiApi.StreamError{kind: :api, status: 500}, 3}
             ] = result
    end

    test "yields error tuple on non-list response" do
      client =
        test_client(fn conn ->
          Req.Test.json(conn, %{"message" => "not a list"})
        end)

      assert [{:error, %UnifiApi.StreamError{kind: :unexpected}, 0}] =
               Client.stream(client, "/v1/test") |> Enum.to_list()
    end

    test "raise_errors: true restores v0.3 raise behaviour" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "boom"}))
        end)

      assert_raise UnifiApi.StreamError, ~r/stream request failed/, fn ->
        Client.stream(client, "/v1/test", raise_errors: true) |> Enum.to_list()
      end
    end

    test "StreamError message does not leak path or body" do
      err =
        UnifiApi.Client.build_stream_error(
          %UnifiApi.ApiError{status: 500, body_preview: "secret"},
          "/v1/sites/abc/devices"
        )

      msg = Exception.message(err)
      refute msg =~ "/v1/sites"
      refute msg =~ "secret"
      assert msg =~ "stream request failed"
    end

    test "build_stream_error/2 classifies each umbrella member" do
      classify = fn reason ->
        err = UnifiApi.Client.build_stream_error(reason, "/v1/sites/abc/devices")
        {err.kind, err.status}
      end

      assert classify.(%UnifiApi.ApiError{status: 503}) == {:api, 503}
      assert classify.(%UnifiApi.ApiError{status: nil}) == {:api, :unknown}
      assert classify.(%UnifiApi.AuthError{status: 401}) == {:auth, 401}
      assert classify.(%UnifiApi.RateLimitError{status: 429}) == {:rate_limit, 429}
      assert classify.(%UnifiApi.TransportError{reason: :econnrefused}) == {:transport, :unknown}
      assert classify.({:unexpected_response, "nope"}) == {:unexpected, :unknown}

      # Reasons also arrive wrapped in an `{:error, _}` tuple depending on
      # which stream variant produced them.
      assert classify.({:error, %UnifiApi.AuthError{status: 403}}) == {:auth, 403}
    end

    test "StreamError never retains a raw response body" do
      # This struct is *returned to the caller* as the stream's final element,
      # so it reaches logs, `inspect/1`, and exception trackers whether or not
      # it is ever raised. `{:unexpected_response, body}` used to retain the
      # entire decoded body verbatim, bypassing the scrubbing every other
      # umbrella member applies (CWE-209 / OWASP A09).
      body =
        Map.new(1..200, fn n ->
          {"field#{n}", "value-#{n} at https://internal.example.com/secret/#{n}"}
        end)

      err = UnifiApi.Client.build_stream_error({:unexpected_response, body}, "/v1/sites/abc")

      assert {:unexpected_response, preview} = err.reason
      assert is_binary(preview)
      assert String.length(preview) <= 128
      refute preview =~ "internal.example.com"

      rendered = inspect(err, limit: :infinity, printable_limit: :infinity)
      refute rendered =~ "internal.example.com"
      assert byte_size(rendered) < 1_000
    end

    test "StreamError funnels an unrecognised reason into the umbrella" do
      err = UnifiApi.Client.build_stream_error(:econnrefused, "/v1/sites/abc")

      assert %UnifiApi.TransportError{reason: :econnrefused} = err.reason
      assert err.kind == :unknown
    end
  end
end
