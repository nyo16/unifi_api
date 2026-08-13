defmodule UnifiApi.ProtectTest do
  use ExUnit.Case, async: true

  defp test_client(plug) do
    Req.new(
      base_url: "http://localhost",
      headers: [{"x-api-key", "test-key"}],
      plug: plug,
      retry: false
    )
  end

  defp assert_request(method, path, extra_assert \\ nil) do
    test_client(fn conn ->
      assert conn.method == method
      assert conn.request_path == "/proxy/protect/integration#{path}"
      # Optional caller-supplied assertion: query params, headers
      # (`x-api-key` / `cookie` / `x-csrf-token`), JSON shape, etc.
      if extra_assert, do: extra_assert.(conn)
      Req.Test.json(conn, %{"ok" => true})
    end)
  end

  defp assert_request_with_body(method, path, extra_assert \\ nil) do
    test_client(fn conn ->
      assert conn.method == method
      assert conn.request_path == "/proxy/protect/integration#{path}"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = JSON.decode!(raw)
      if extra_assert, do: extra_assert.(body)
      Req.Test.json(conn, %{"ok" => true, "body" => body})
    end)
  end

  # Shared error plug: respond with `status` and a JSON `body`, exercising
  # the umbrella's error-tuple coverage in one representative test per
  # module surface. `retry: false` is critical — Req backoffs on 429/5xx
  # would otherwise time the test out at the default 60s ceiling.
  #
  # `opts` keeps this the *only* error helper in the file:
  #
  #   * `:headers` — response headers, e.g. `Retry-After` on the 429 paths
  #   * `:method` — asserts the request verb, so a mutating-verb test cannot
  #     silently pass against a GET issued by the wrong function
  defp error_client(status, body, opts \\ []) do
    expected_method = Keyword.get(opts, :method)
    resp_headers = Keyword.get(opts, :headers, [])

    Req.new(
      base_url: "http://localhost",
      headers: [{"x-api-key", "test-key"}],
      plug: fn conn ->
        if expected_method, do: assert(conn.method == expected_method)

        conn = Plug.Conn.put_resp_content_type(conn, "application/json")

        resp_headers
        |> Enum.reduce(conn, fn {name, value}, acc ->
          Plug.Conn.put_resp_header(acc, name, value)
        end)
        |> Plug.Conn.send_resp(status, body)
      end,
      retry: false
    )
  end

  # --- Cameras ---

  describe "Cameras" do
    test "list/1" do
      client = assert_request("GET", "/v1/cameras")
      assert {:ok, _} = UnifiApi.Protect.Cameras.list(client)
    end

    test "get/2" do
      client = assert_request("GET", "/v1/cameras/cam-1")
      assert {:ok, _} = UnifiApi.Protect.Cameras.get(client, "cam-1")
    end

    test "update/3" do
      client = assert_request_with_body("PATCH", "/v1/cameras/cam-1")

      assert {:ok, %{"body" => %{"name" => "Front Door"}}} =
               UnifiApi.Protect.Cameras.update(client, "cam-1", %{name: "Front Door"})
    end

    test "snapshot/3 returns raw binary" do
      client =
        test_client(fn conn ->
          assert conn.method == "GET"
          assert conn.request_path == "/proxy/protect/integration/v1/cameras/cam-1/snapshot"

          conn
          |> Plug.Conn.put_resp_content_type("image/jpeg")
          |> Plug.Conn.send_resp(200, <<0xFF, 0xD8, 0xFF>>)
        end)

      assert {:ok, <<0xFF, 0xD8, 0xFF>>} = UnifiApi.Protect.Cameras.snapshot(client, "cam-1")
    end

    test "snapshot/3 passes highQuality param" do
      client =
        test_client(fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["highQuality"] == "true"

          conn
          |> Plug.Conn.put_resp_content_type("image/jpeg")
          |> Plug.Conn.send_resp(200, <<0xFF>>)
        end)

      assert {:ok, _} = UnifiApi.Protect.Cameras.snapshot(client, "cam-1", high_quality: true)
    end

    test "ptz_patrol_start/3" do
      client = assert_request_with_body("POST", "/v1/cameras/cam-1/ptz/patrol/start/2")

      assert {:ok, _} = UnifiApi.Protect.Cameras.ptz_patrol_start(client, "cam-1", 2)
    end

    test "ptz_patrol_stop/2" do
      client = assert_request_with_body("POST", "/v1/cameras/cam-1/ptz/patrol/stop")

      assert {:ok, _} = UnifiApi.Protect.Cameras.ptz_patrol_stop(client, "cam-1")
    end

    test "ptz_goto/3" do
      client = assert_request_with_body("POST", "/v1/cameras/cam-1/ptz/goto/5")

      assert {:ok, _} = UnifiApi.Protect.Cameras.ptz_goto(client, "cam-1", 5)
    end
  end

  # --- NVR ---

  describe "NVR" do
    test "get/1" do
      client = assert_request("GET", "/v1/nvrs")
      assert {:ok, _} = UnifiApi.Protect.NVR.get(client)
    end
  end

  # --- Viewers ---

  describe "Viewers" do
    test "list/1" do
      client = assert_request("GET", "/v1/viewers")
      assert {:ok, _} = UnifiApi.Protect.Viewers.list(client)
    end

    test "list/2 forwards :limit, :offset and :filter to the query string" do
      client =
        assert_request("GET", "/v1/viewers", fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["limit"] == "50"
          assert params["offset"] == "100"
          assert params["filter"] == "state.eq(CONNECTED)"
        end)

      assert {:ok, _} =
               UnifiApi.Protect.Viewers.list(client,
                 limit: 50,
                 offset: 100,
                 filter: "state.eq(CONNECTED)"
               )
    end

    test "list/2 rejects an unknown option instead of dropping it" do
      client = assert_request("GET", "/v1/viewers")

      assert_raise ArgumentError, fn ->
        UnifiApi.Protect.Viewers.list(client, page_size: 50)
      end
    end

    test "get/2" do
      client = assert_request("GET", "/v1/viewers/v1")
      assert {:ok, _} = UnifiApi.Protect.Viewers.get(client, "v1")
    end

    test "update/3" do
      client = assert_request_with_body("PATCH", "/v1/viewers/v1")

      assert {:ok, %{"body" => %{"liveview" => "lv-1"}}} =
               UnifiApi.Protect.Viewers.update(client, "v1", %{liveview: "lv-1"})
    end
  end

  # --- Liveviews ---

  describe "Liveviews" do
    test "list/1" do
      client = assert_request("GET", "/v1/liveviews")
      assert {:ok, _} = UnifiApi.Protect.Liveviews.list(client)
    end

    test "list/2 forwards :params verbatim" do
      client =
        assert_request("GET", "/v1/liveviews", fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["isGlobal"] == "true"
        end)

      assert {:ok, _} = UnifiApi.Protect.Liveviews.list(client, params: [isGlobal: true])
    end

    test "get/2" do
      client = assert_request("GET", "/v1/liveviews/lv-1")
      assert {:ok, _} = UnifiApi.Protect.Liveviews.get(client, "lv-1")
    end
  end

  # --- Sensors ---

  describe "Sensors" do
    test "list/1" do
      client = assert_request("GET", "/v1/sensors")
      assert {:ok, _} = UnifiApi.Protect.Sensors.list(client)
    end

    test "list/2 forwards :limit and :offset to the query string" do
      client =
        assert_request("GET", "/v1/sensors", fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["limit"] == "200"
          assert params["offset"] == "200"
        end)

      assert {:ok, _} = UnifiApi.Protect.Sensors.list(client, limit: 200, offset: 200)
    end

    test "get/2" do
      client = assert_request("GET", "/v1/sensors/sensor-1")
      assert {:ok, _} = UnifiApi.Protect.Sensors.get(client, "sensor-1")
    end

    test "update/3" do
      client = assert_request_with_body("PATCH", "/v1/sensors/sensor-1")

      assert {:ok, %{"body" => %{"name" => "Door Sensor"}}} =
               UnifiApi.Protect.Sensors.update(client, "sensor-1", %{name: "Door Sensor"})
    end
  end

  # --- Lights ---

  describe "Lights" do
    test "list/1" do
      client = assert_request("GET", "/v1/lights")
      assert {:ok, _} = UnifiApi.Protect.Lights.list(client)
    end

    test "list/2 forwards :filter to the query string" do
      client =
        assert_request("GET", "/v1/lights", fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["filter"] == "isLightOn.eq(true)"
        end)

      assert {:ok, _} = UnifiApi.Protect.Lights.list(client, filter: "isLightOn.eq(true)")
    end

    test "get/2" do
      client = assert_request("GET", "/v1/lights/light-1")
      assert {:ok, _} = UnifiApi.Protect.Lights.get(client, "light-1")
    end

    test "update/3" do
      client = assert_request_with_body("PATCH", "/v1/lights/light-1")

      assert {:ok, %{"body" => %{"name" => "Porch Light"}}} =
               UnifiApi.Protect.Lights.update(client, "light-1", %{name: "Porch Light"})
    end
  end

  # --- Chimes ---

  describe "Chimes" do
    test "list/1" do
      client = assert_request("GET", "/v1/chimes")
      assert {:ok, _} = UnifiApi.Protect.Chimes.list(client)
    end

    test "list/2 with :raw skips JSON decoding" do
      client = assert_request("GET", "/v1/chimes")

      assert {:ok, body} = UnifiApi.Protect.Chimes.list(client, raw: true)
      assert is_binary(body)
      assert body == ~s({"ok":true})
    end

    test "get/2" do
      client = assert_request("GET", "/v1/chimes/chime-1")
      assert {:ok, _} = UnifiApi.Protect.Chimes.get(client, "chime-1")
    end

    test "update/3" do
      client = assert_request_with_body("PATCH", "/v1/chimes/chime-1")

      assert {:ok, %{"body" => %{"volume" => 80}}} =
               UnifiApi.Protect.Chimes.update(client, "chime-1", %{volume: 80})
    end
  end

  # --- Protect Streams ---

  describe "Protect Streams" do
    defp stream_client(path) do
      page_count = :counters.new(1, [:atomics])

      test_client(fn conn ->
        assert conn.request_path == "/proxy/protect/integration#{path}"
        :counters.add(page_count, 1, 1)
        params = Plug.Conn.fetch_query_params(conn).query_params
        offset = String.to_integer(params["offset"] || "0")

        items =
          if offset == 0,
            do: [%{"id" => "a"}, %{"id" => "b"}],
            else: [%{"id" => "c"}]

        Req.Test.json(conn, items)
      end)
    end

    test "Sensors.stream/1" do
      client = stream_client("/v1/sensors")
      result = UnifiApi.Protect.Sensors.stream(client, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Lights.stream/1" do
      client = stream_client("/v1/lights")
      result = UnifiApi.Protect.Lights.stream(client, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Chimes.stream/1" do
      client = stream_client("/v1/chimes")
      result = UnifiApi.Protect.Chimes.stream(client, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Liveviews.stream/1" do
      client = stream_client("/v1/liveviews")
      result = UnifiApi.Protect.Liveviews.stream(client, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end
  end

  # --- Error paths (one representative test per surface) ---

  describe "error paths" do
    test "Cameras.list/1 surfaces AuthError on 401" do
      client = error_client(401, JSON.encode!(%{"error" => "bad key"}))

      assert {:error, %UnifiApi.AuthError{status: 401, reason: :unauthorized}} =
               UnifiApi.Protect.Cameras.list(client)
    end

    test "Cameras.get/2 surfaces AuthError on 403" do
      client = error_client(403, JSON.encode!(%{"error" => "no access"}))

      assert {:error, %UnifiApi.AuthError{status: 403, reason: :forbidden}} =
               UnifiApi.Protect.Cameras.get(client, "cam-1")
    end

    test "Cameras.list/1 surfaces RateLimitError on 429" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "45")
          |> Plug.Conn.send_resp(429, "{}")
        end)

      assert {:error, %UnifiApi.RateLimitError{retry_after: 45, status: 429}} =
               UnifiApi.Protect.Cameras.list(client)
    end

    test "Cameras.get/2 surfaces %ApiError{} on 404" do
      client = error_client(404, JSON.encode!(%{"error" => "missing"}))

      assert {:error, %UnifiApi.ApiError{status: 404, code: nil, body_preview: preview}} =
               UnifiApi.Protect.Cameras.get(client, "cam-1")

      # Body is scrubbed/truncated into a preview string, never the raw map.
      assert preview =~ "missing"
    end

    test "Cameras.snapshot/2 surfaces %ApiError{} on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "boom"}))

      assert {:error, %UnifiApi.ApiError{status: 500, code: nil, body_preview: preview}} =
               UnifiApi.Protect.Cameras.snapshot(client, "cam-1")

      # Body is scrubbed/truncated into a preview string, never the raw map.
      assert preview =~ "boom"
    end
  end

  # --- Path-segment boundary enforcement (CWE-22 / OWASP A03) ---
  #
  # `Client.validate_id!/1` is unit-tested at its definition site in
  # client_test.exs; these tests pin the *enforcement* sites, so dropping
  # the call from a resource module fails the suite instead of passing
  # silently. The plug flunks if it is ever invoked, which proves the
  # raise happens during path composition, before any request is issued.
  # Protect paths carry no site id and expose no DELETE, so the mutating
  # coverage is PATCH (`update/3`) and POST (`ptz_patrol_stop/2`).

  describe "resource-boundary id validation" do
    @traversal "../../users"

    defp no_request_client do
      test_client(fn conn ->
        flunk("request was issued to #{conn.request_path} instead of raising")
      end)
    end

    test "Cameras.get/2 rejects a traversal camera id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Protect.Cameras.get(no_request_client(), @traversal)
      end
    end

    test "Cameras.update/3 rejects a traversal camera id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Protect.Cameras.update(no_request_client(), @traversal, %{name: "Front Door"})
      end
    end

    test "Cameras.snapshot/3 rejects a traversal camera id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Protect.Cameras.snapshot(no_request_client(), @traversal)
      end
    end

    test "Cameras.ptz_patrol_stop/2 rejects a traversal camera id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Protect.Cameras.ptz_patrol_stop(no_request_client(), @traversal)
      end
    end

    test "Viewers.update/3 rejects a non-binary viewer id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Protect.Viewers.update(no_request_client(), :viewer_1, %{name: "Wall"})
      end
    end

    test "Cameras.ptz_goto/3 rejects a string slot" do
      # Called through `apply/3`: a literal string here is exactly the
      # attack the guard blocks, but the compiler's type checker would
      # (correctly) warn about it at build time and the suite must stay
      # warning-free.
      args = [no_request_client(), "cam-1", "1/../../users"]

      assert_raise FunctionClauseError, fn ->
        apply(UnifiApi.Protect.Cameras, :ptz_goto, args)
      end
    end

    test "Cameras.ptz_patrol_start/3 rejects a negative slot" do
      assert_raise FunctionClauseError, fn ->
        UnifiApi.Protect.Cameras.ptz_patrol_start(no_request_client(), "cam-1", -1)
      end
    end
  end

  # --- Mutating-verb error paths ---
  #
  # Protect exposes no PUT/DELETE: every write is a PATCH (`update/3`) or a
  # POST (the PTZ commands), so those are the verbs pinned here. Before
  # v0.4.0 not one of them had a non-2xx test. `error_client/3` asserts the
  # verb so a test cannot pass against a GET issued by the wrong function.

  describe "mutating-verb error paths" do
    test "Lights.update/3 (PATCH) surfaces ApiError on 409" do
      client =
        error_client(409, JSON.encode!(%{"error" => "light is offline"}), method: "PATCH")

      assert {:error, %UnifiApi.ApiError{status: 409, body_preview: preview}} =
               UnifiApi.Protect.Lights.update(client, "light-1", %{lightModeSettings: %{}})

      assert preview =~ "light is offline"
    end

    test "Sensors.update/3 (PATCH) surfaces AuthError on 401" do
      client = error_client(401, JSON.encode!(%{"error" => "bad key"}), method: "PATCH")

      assert {:error, %UnifiApi.AuthError{status: 401, reason: :unauthorized}} =
               UnifiApi.Protect.Sensors.update(client, "sensor-1", %{name: "Garage"})
    end

    test "Viewers.update/3 (PATCH) surfaces AuthError on 403" do
      client = error_client(403, JSON.encode!(%{"error" => "read-only admin"}), method: "PATCH")

      assert {:error, %UnifiApi.AuthError{status: 403, reason: :forbidden}} =
               UnifiApi.Protect.Viewers.update(client, "viewer-1", %{liveview: "lv-1"})
    end

    test "Chimes.update/3 (PATCH) surfaces RateLimitError with parsed Retry-After on 429" do
      client = error_client(429, "{}", method: "PATCH", headers: [{"retry-after", "20"}])

      assert {:error, %UnifiApi.RateLimitError{status: 429, retry_after: 20}} =
               UnifiApi.Protect.Chimes.update(client, "chime-1", %{volume: 80})
    end

    test "Cameras.update/3 (PATCH) surfaces ApiError on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "boom"}), method: "PATCH")

      assert {:error, %UnifiApi.ApiError{status: 500}} =
               UnifiApi.Protect.Cameras.update(client, "cam-1", %{name: "Front Door"})
    end

    test "Cameras.ptz_patrol_stop/2 (POST) clamps an absurd Retry-After to 300s on 429" do
      client = error_client(429, "{}", method: "POST", headers: [{"retry-after", "99999"}])

      assert {:error, %UnifiApi.RateLimitError{status: 429, retry_after: 300}} =
               UnifiApi.Protect.Cameras.ptz_patrol_stop(client, "cam-1")
    end

    test "Cameras.ptz_goto/3 (POST) surfaces ApiError on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "ptz busy"}), method: "POST")

      assert {:error, %UnifiApi.ApiError{status: 500}} =
               UnifiApi.Protect.Cameras.ptz_goto(client, "cam-1", 1)
    end

    test "Cameras.ptz_patrol_start/3 (POST) surfaces AuthError on 403" do
      client = error_client(403, JSON.encode!(%{"error" => "no ptz rights"}), method: "POST")

      assert {:error, %UnifiApi.AuthError{status: 403, reason: :forbidden}} =
               UnifiApi.Protect.Cameras.ptz_patrol_start(client, "cam-1", 2)
    end

    # The remaining umbrella member reachable from a mutating verb.
    # `Client.patch/4`'s own wrapping is unit-tested in
    # transport_error_test.exs; this pins that a *resource* module does not
    # unwrap or reshape it on the way back out.
    test "Cameras.update/3 (PATCH) wraps a transport failure in TransportError" do
      client = test_client(fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error,
              %UnifiApi.TransportError{
                reason: :timeout,
                original: %Req.TransportError{reason: :timeout}
              }} = UnifiApi.Protect.Cameras.update(client, "cam-1", %{name: "Front Door"})
    end

    # CWE-209: a controller error body can echo internal infrastructure.
    # `Client.scrub_body_preview/1` runs on the ApiError path too, so the
    # preview must never carry the URL verbatim.
    test "Lights.update/3 scrubs a leaked URL out of ApiError body_preview" do
      leaked = "https://internal.example.com/secret"

      client =
        error_client(
          500,
          JSON.encode!(%{"error" => "upstream failed", "detail" => "see #{leaked}"}),
          method: "PATCH"
        )

      assert {:error, %UnifiApi.ApiError{status: 500, body_preview: preview}} =
               UnifiApi.Protect.Lights.update(client, "light-1", %{name: "Porch"})

      refute preview =~ leaked
      refute preview =~ "internal.example.com"
      assert preview =~ "[url]"
    end
  end

  # --- Module error-path coverage ---
  #
  # Read surfaces that had zero error-path coverage before v0.4.0: Lights,
  # Sensors, Viewers, Chimes, Liveviews, Events and NVR. Only Cameras was
  # covered, which left every other Protect module free to regress.

  describe "module error-path coverage" do
    test "Lights.list/1 surfaces ApiError on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "boom"}), method: "GET")

      assert {:error, %UnifiApi.ApiError{status: 500}} = UnifiApi.Protect.Lights.list(client)
    end

    test "Sensors.get/2 surfaces ApiError on 404" do
      client = error_client(404, JSON.encode!(%{"error" => "missing"}))

      assert {:error, %UnifiApi.ApiError{status: 404}} =
               UnifiApi.Protect.Sensors.get(client, "sensor-1")
    end

    test "Viewers.list/1 surfaces AuthError on 401" do
      client = error_client(401, JSON.encode!(%{"error" => "bad key"}))

      assert {:error, %UnifiApi.AuthError{status: 401, reason: :unauthorized}} =
               UnifiApi.Protect.Viewers.list(client)
    end

    test "Chimes.list/1 surfaces RateLimitError on 429" do
      client = error_client(429, "{}", headers: [{"retry-after", "15"}])

      assert {:error, %UnifiApi.RateLimitError{status: 429, retry_after: 15}} =
               UnifiApi.Protect.Chimes.list(client)
    end

    test "Liveviews.list/1 surfaces AuthError on 403" do
      client = error_client(403, JSON.encode!(%{"error" => "no access"}))

      assert {:error, %UnifiApi.AuthError{status: 403, reason: :forbidden}} =
               UnifiApi.Protect.Liveviews.list(client)
    end

    test "Events.list/2 surfaces ApiError on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "boom"}))

      assert {:error, %UnifiApi.ApiError{status: 500}} = UnifiApi.Protect.Events.list(client)
    end

    test "NVR.get/2 surfaces ApiError on 503" do
      client = error_client(503, JSON.encode!(%{"error" => "upgrading"}))

      assert {:error, %UnifiApi.ApiError{status: 503}} = UnifiApi.Protect.NVR.get(client)
    end
  end
end
