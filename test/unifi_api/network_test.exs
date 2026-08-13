defmodule UnifiApi.NetworkTest do
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
      assert conn.request_path == "/proxy/network/integration#{path}"
      # Optional caller-supplied assertion: query params, headers
      # (`x-api-key` / `cookie` / `x-csrf-token`), JSON shape, etc.
      if extra_assert, do: extra_assert.(conn)
      Req.Test.json(conn, %{"ok" => true})
    end)
  end

  defp stream_client(path) do
    test_client(fn conn ->
      assert conn.request_path == "/proxy/network/integration#{path}"
      params = Plug.Conn.fetch_query_params(conn).query_params
      offset = String.to_integer(params["offset"] || "0")

      items =
        if offset == 0,
          do: [%{"id" => 1}, %{"id" => 2}],
          else: [%{"id" => 3}]

      Req.Test.json(conn, items)
    end)
  end

  defp assert_request_with_body(method, path, extra_assert \\ nil) do
    test_client(fn conn ->
      assert conn.method == method
      assert conn.request_path == "/proxy/network/integration#{path}"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = JSON.decode!(raw)
      if extra_assert, do: extra_assert.(body)
      Req.Test.json(conn, %{"ok" => true, "body" => body})
    end)
  end

  # Shared error plug: respond with `status` and a JSON `body`, exercising
  # the umbrella's error-tuple coverage in one representative test per
  # module. `retry: false` is critical — Req backoffs on 429/5xx would
  # otherwise time the test out at the default 60s ceiling.
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

  # --- Info ---

  describe "Info" do
    test "get_info/1" do
      client = assert_request("GET", "/v1/info")
      assert {:ok, _} = UnifiApi.Network.Info.get_info(client)
    end
  end

  # --- Sites ---

  describe "Sites" do
    test "list/2" do
      client = assert_request("GET", "/v1/sites")
      assert {:ok, _} = UnifiApi.Network.Sites.list(client)
    end
  end

  # --- Devices ---

  describe "Devices" do
    @site "site-1"

    test "list/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/devices")
      assert {:ok, _} = UnifiApi.Network.Devices.list(client, @site)
    end

    test "get/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/devices/dev-1")
      assert {:ok, _} = UnifiApi.Network.Devices.get(client, @site, "dev-1")
    end

    test "adopt/4" do
      client = assert_request_with_body("POST", "/v1/sites/#{@site}/devices")

      assert {:ok, %{"body" => %{"mac" => "aa:bb:cc"}}} =
               UnifiApi.Network.Devices.adopt(client, @site, %{mac: "aa:bb:cc"})
    end

    test "remove/3" do
      client = assert_request("DELETE", "/v1/sites/#{@site}/devices/dev-1")
      assert {:ok, _} = UnifiApi.Network.Devices.remove(client, @site, "dev-1")
    end

    test "get_statistics/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/devices/dev-1/statistics/latest")
      assert {:ok, _} = UnifiApi.Network.Devices.get_statistics(client, @site, "dev-1")
    end

    test "execute_action/4" do
      client = assert_request_with_body("POST", "/v1/sites/#{@site}/devices/dev-1/actions")

      assert {:ok, %{"body" => %{"action" => "restart"}}} =
               UnifiApi.Network.Devices.execute_action(client, @site, "dev-1", %{
                 action: "restart"
               })
    end

    test "execute_port_action/5" do
      client =
        assert_request_with_body(
          "POST",
          "/v1/sites/#{@site}/devices/dev-1/interfaces/ports/3/actions"
        )

      assert {:ok, %{"body" => %{"action" => "cycle"}}} =
               UnifiApi.Network.Devices.execute_port_action(client, @site, "dev-1", 3, %{
                 action: "cycle"
               })
    end

    test "list_pending/2" do
      client = assert_request("GET", "/v1/pending-devices")
      assert {:ok, _} = UnifiApi.Network.Devices.list_pending(client)
    end
  end

  # --- Clients ---

  describe "Clients" do
    test "list/3" do
      client = assert_request("GET", "/v1/sites/s1/clients")
      assert {:ok, _} = UnifiApi.Network.Clients.list(client, "s1")
    end
  end

  # --- Networks ---

  describe "Networks" do
    @site "site-1"

    test "list/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/networks")
      assert {:ok, _} = UnifiApi.Network.Networks.list(client, @site)
    end

    test "get/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/networks/net-1")
      assert {:ok, _} = UnifiApi.Network.Networks.get(client, @site, "net-1")
    end

    test "create/3" do
      client = assert_request_with_body("POST", "/v1/sites/#{@site}/networks")

      assert {:ok, %{"body" => %{"name" => "LAN"}}} =
               UnifiApi.Network.Networks.create(client, @site, %{name: "LAN"})
    end

    test "update/4" do
      client = assert_request_with_body("PUT", "/v1/sites/#{@site}/networks/net-1")

      assert {:ok, %{"body" => %{"name" => "LAN2"}}} =
               UnifiApi.Network.Networks.update(client, @site, "net-1", %{name: "LAN2"})
    end

    test "delete/4" do
      client = assert_request("DELETE", "/v1/sites/#{@site}/networks/net-1")
      assert {:ok, _} = UnifiApi.Network.Networks.delete(client, @site, "net-1")
    end
  end

  # --- Wifi ---

  describe "Wifi" do
    test "list/3" do
      client = assert_request("GET", "/v1/sites/s1/wifi/broadcasts")
      assert {:ok, _} = UnifiApi.Network.Wifi.list(client, "s1")
    end
  end

  # --- Firewall ---

  describe "Firewall zones" do
    @site "site-1"

    test "list_zones/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/firewall/zones")
      assert {:ok, _} = UnifiApi.Network.Firewall.list_zones(client, @site)
    end

    test "get_zone/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/firewall/zones/z1")
      assert {:ok, _} = UnifiApi.Network.Firewall.get_zone(client, @site, "z1")
    end

    test "create_zone/3" do
      client = assert_request_with_body("POST", "/v1/sites/#{@site}/firewall/zones")

      assert {:ok, %{"body" => %{"name" => "DMZ"}}} =
               UnifiApi.Network.Firewall.create_zone(client, @site, %{name: "DMZ"})
    end

    test "update_zone/4" do
      client = assert_request_with_body("PUT", "/v1/sites/#{@site}/firewall/zones/z1")

      assert {:ok, %{"body" => %{"name" => "DMZ2"}}} =
               UnifiApi.Network.Firewall.update_zone(client, @site, "z1", %{name: "DMZ2"})
    end

    test "delete_zone/3" do
      client = assert_request("DELETE", "/v1/sites/#{@site}/firewall/zones/z1")
      assert {:ok, _} = UnifiApi.Network.Firewall.delete_zone(client, @site, "z1")
    end
  end

  describe "Firewall policies" do
    @site "site-1"

    test "list_policies/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/firewall/policies")
      assert {:ok, _} = UnifiApi.Network.Firewall.list_policies(client, @site)
    end

    test "get_policy/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/firewall/policies/p1")
      assert {:ok, _} = UnifiApi.Network.Firewall.get_policy(client, @site, "p1")
    end

    test "create_policy/3" do
      client = assert_request_with_body("POST", "/v1/sites/#{@site}/firewall/policies")

      assert {:ok, %{"body" => %{"action" => "BLOCK"}}} =
               UnifiApi.Network.Firewall.create_policy(client, @site, %{action: "BLOCK"})
    end

    test "update_policy/4" do
      client = assert_request_with_body("PUT", "/v1/sites/#{@site}/firewall/policies/p1")

      assert {:ok, %{"body" => %{"action" => "ALLOW"}}} =
               UnifiApi.Network.Firewall.update_policy(client, @site, "p1", %{action: "ALLOW"})
    end

    test "delete_policy/3" do
      client = assert_request("DELETE", "/v1/sites/#{@site}/firewall/policies/p1")
      assert {:ok, _} = UnifiApi.Network.Firewall.delete_policy(client, @site, "p1")
    end
  end

  # --- Hotspot ---

  describe "Hotspot" do
    @site "site-1"

    test "list_vouchers/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/hotspot/vouchers")
      assert {:ok, _} = UnifiApi.Network.Hotspot.list_vouchers(client, @site)
    end

    test "get_voucher/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/hotspot/vouchers/v1")
      assert {:ok, _} = UnifiApi.Network.Hotspot.get_voucher(client, @site, "v1")
    end

    test "create_vouchers/3" do
      client = assert_request_with_body("POST", "/v1/sites/#{@site}/hotspot/vouchers")

      assert {:ok, %{"body" => %{"count" => 5}}} =
               UnifiApi.Network.Hotspot.create_vouchers(client, @site, %{count: 5})
    end

    test "delete_vouchers/3" do
      client = assert_request("DELETE", "/v1/sites/#{@site}/hotspot/vouchers")
      assert {:ok, _} = UnifiApi.Network.Hotspot.delete_vouchers(client, @site)
    end

    test "delete_voucher/3" do
      client = assert_request("DELETE", "/v1/sites/#{@site}/hotspot/vouchers/v1")
      assert {:ok, _} = UnifiApi.Network.Hotspot.delete_voucher(client, @site, "v1")
    end
  end

  # --- ACL ---

  describe "ACL" do
    @site "site-1"

    test "list/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/acl-rules")
      assert {:ok, _} = UnifiApi.Network.ACL.list(client, @site)
    end

    test "get/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/acl-rules/r1")
      assert {:ok, _} = UnifiApi.Network.ACL.get(client, @site, "r1")
    end

    test "create/3" do
      client = assert_request_with_body("POST", "/v1/sites/#{@site}/acl-rules")

      assert {:ok, %{"body" => %{"action" => "BLOCK"}}} =
               UnifiApi.Network.ACL.create(client, @site, %{action: "BLOCK"})
    end

    test "update/4" do
      client = assert_request_with_body("PUT", "/v1/sites/#{@site}/acl-rules/r1")

      assert {:ok, %{"body" => %{"action" => "ALLOW"}}} =
               UnifiApi.Network.ACL.update(client, @site, "r1", %{action: "ALLOW"})
    end

    test "delete/3" do
      client = assert_request("DELETE", "/v1/sites/#{@site}/acl-rules/r1")
      assert {:ok, _} = UnifiApi.Network.ACL.delete(client, @site, "r1")
    end

    test "get_ordering/2" do
      client = assert_request("GET", "/v1/sites/#{@site}/acl-rules/ordering")
      assert {:ok, _} = UnifiApi.Network.ACL.get_ordering(client, @site)
    end

    test "update_ordering/3" do
      client = assert_request_with_body("PUT", "/v1/sites/#{@site}/acl-rules/ordering")

      assert {:ok, %{"body" => %{"ids" => ["a", "b"]}}} =
               UnifiApi.Network.ACL.update_ordering(client, @site, %{ids: ["a", "b"]})
    end
  end

  # --- DNS ---

  describe "DNS" do
    @site "site-1"

    test "list/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/dns/policies")
      assert {:ok, _} = UnifiApi.Network.DNS.list(client, @site)
    end

    test "get/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/dns/policies/d1")
      assert {:ok, _} = UnifiApi.Network.DNS.get(client, @site, "d1")
    end

    test "create/3" do
      client = assert_request_with_body("POST", "/v1/sites/#{@site}/dns/policies")

      assert {:ok, %{"body" => %{"type" => "A_RECORD"}}} =
               UnifiApi.Network.DNS.create(client, @site, %{type: "A_RECORD"})
    end

    test "update/4" do
      client = assert_request_with_body("PUT", "/v1/sites/#{@site}/dns/policies/d1")

      assert {:ok, %{"body" => %{"type" => "CNAME_RECORD"}}} =
               UnifiApi.Network.DNS.update(client, @site, "d1", %{type: "CNAME_RECORD"})
    end

    test "delete/3" do
      client = assert_request("DELETE", "/v1/sites/#{@site}/dns/policies/d1")
      assert {:ok, _} = UnifiApi.Network.DNS.delete(client, @site, "d1")
    end
  end

  # --- TrafficMatching ---

  describe "TrafficMatching" do
    test "list/3" do
      client = assert_request("GET", "/v1/sites/s1/traffic-matching-lists")
      assert {:ok, _} = UnifiApi.Network.TrafficMatching.list(client, "s1")
    end
  end

  # --- Resources ---

  describe "Resources" do
    @site "site-1"

    test "list_wans/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/wans")
      assert {:ok, _} = UnifiApi.Network.Resources.list_wans(client, @site)
    end

    test "list_vpn_tunnels/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/vpn/site-to-site-tunnels")
      assert {:ok, _} = UnifiApi.Network.Resources.list_vpn_tunnels(client, @site)
    end

    test "list_vpn_servers/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/vpn/servers")
      assert {:ok, _} = UnifiApi.Network.Resources.list_vpn_servers(client, @site)
    end

    test "list_radius_profiles/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/radius/profiles")
      assert {:ok, _} = UnifiApi.Network.Resources.list_radius_profiles(client, @site)
    end

    test "list_device_tags/3" do
      client = assert_request("GET", "/v1/sites/#{@site}/device-tags")
      assert {:ok, _} = UnifiApi.Network.Resources.list_device_tags(client, @site)
    end

    test "list_dpi_categories/2" do
      client = assert_request("GET", "/v1/dpi/categories")
      assert {:ok, _} = UnifiApi.Network.Resources.list_dpi_categories(client)
    end

    test "list_dpi_applications/2" do
      client = assert_request("GET", "/v1/dpi/applications")
      assert {:ok, _} = UnifiApi.Network.Resources.list_dpi_applications(client)
    end

    test "list_countries/2" do
      client = assert_request("GET", "/v1/countries")
      assert {:ok, _} = UnifiApi.Network.Resources.list_countries(client)
    end
  end

  # --- Stream tests ---

  describe "stream" do
    @site "site-1"

    test "Sites.stream/2" do
      client = stream_client("/v1/sites")
      assert [_, _, _] = UnifiApi.Network.Sites.stream(client, limit: 2) |> Enum.to_list()
    end

    test "Devices.stream/3" do
      client = stream_client("/v1/sites/#{@site}/devices")

      result = UnifiApi.Network.Devices.stream(client, @site, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Devices.stream_pending/2" do
      client = stream_client("/v1/pending-devices")

      result = UnifiApi.Network.Devices.stream_pending(client, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Clients.stream/3" do
      client = stream_client("/v1/sites/#{@site}/clients")

      result = UnifiApi.Network.Clients.stream(client, @site, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Networks.stream/3" do
      client = stream_client("/v1/sites/#{@site}/networks")

      result = UnifiApi.Network.Networks.stream(client, @site, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Wifi.stream/3" do
      client = stream_client("/v1/sites/#{@site}/wifi/broadcasts")

      result = UnifiApi.Network.Wifi.stream(client, @site, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Firewall.stream_zones/3" do
      client = stream_client("/v1/sites/#{@site}/firewall/zones")

      result =
        UnifiApi.Network.Firewall.stream_zones(client, @site, limit: 2) |> Enum.to_list()

      assert length(result) == 3
    end

    test "Firewall.stream_policies/3" do
      client = stream_client("/v1/sites/#{@site}/firewall/policies")

      result =
        UnifiApi.Network.Firewall.stream_policies(client, @site, limit: 2) |> Enum.to_list()

      assert length(result) == 3
    end

    test "Hotspot.stream_vouchers/3" do
      client = stream_client("/v1/sites/#{@site}/hotspot/vouchers")

      result =
        UnifiApi.Network.Hotspot.stream_vouchers(client, @site, limit: 2) |> Enum.to_list()

      assert length(result) == 3
    end

    test "ACL.stream/3" do
      client = stream_client("/v1/sites/#{@site}/acl-rules")

      result = UnifiApi.Network.ACL.stream(client, @site, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "DNS.stream/3" do
      client = stream_client("/v1/sites/#{@site}/dns/policies")

      result = UnifiApi.Network.DNS.stream(client, @site, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "TrafficMatching.stream/3" do
      client = stream_client("/v1/sites/#{@site}/traffic-matching-lists")

      result =
        UnifiApi.Network.TrafficMatching.stream(client, @site, limit: 2) |> Enum.to_list()

      assert length(result) == 3
    end

    test "Resources.stream_wans/3" do
      client = stream_client("/v1/sites/#{@site}/wans")

      result = UnifiApi.Network.Resources.stream_wans(client, @site, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Resources.stream_dpi_categories/2" do
      client = stream_client("/v1/dpi/categories")

      result =
        UnifiApi.Network.Resources.stream_dpi_categories(client, limit: 2) |> Enum.to_list()

      assert length(result) == 3
    end

    test "Resources.stream_countries/2" do
      client = stream_client("/v1/countries")

      result = UnifiApi.Network.Resources.stream_countries(client, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Resources.stream_vpn_tunnels/3" do
      client = stream_client("/v1/sites/#{@site}/vpn/site-to-site-tunnels")

      result =
        UnifiApi.Network.Resources.stream_vpn_tunnels(client, @site, limit: 2) |> Enum.to_list()

      assert length(result) == 3
    end

    test "Resources.stream_vpn_servers/3" do
      client = stream_client("/v1/sites/#{@site}/vpn/servers")

      result =
        UnifiApi.Network.Resources.stream_vpn_servers(client, @site, limit: 2) |> Enum.to_list()

      assert length(result) == 3
    end

    test "Resources.stream_radius_profiles/3" do
      client = stream_client("/v1/sites/#{@site}/radius/profiles")

      result =
        UnifiApi.Network.Resources.stream_radius_profiles(client, @site, limit: 2)
        |> Enum.to_list()

      assert length(result) == 3
    end

    test "Resources.stream_device_tags/3" do
      client = stream_client("/v1/sites/#{@site}/device-tags")

      result =
        UnifiApi.Network.Resources.stream_device_tags(client, @site, limit: 2) |> Enum.to_list()

      assert length(result) == 3
    end

    test "Resources.stream_dpi_applications/2" do
      client = stream_client("/v1/dpi/applications")

      result =
        UnifiApi.Network.Resources.stream_dpi_applications(client, limit: 2) |> Enum.to_list()

      assert length(result) == 3
    end
  end

  # --- Error paths (one representative test per surface) ---

  describe "error paths" do
    test "Sites.list/1 surfaces AuthError on 401" do
      client = error_client(401, JSON.encode!(%{"error" => "bad key"}))

      assert {:error, %UnifiApi.AuthError{status: 401, reason: :unauthorized}} =
               UnifiApi.Network.Sites.list(client)
    end

    test "Devices.list/2 surfaces AuthError on 403" do
      client = error_client(403, JSON.encode!(%{"error" => "no access"}))

      assert {:error, %UnifiApi.AuthError{status: 403, reason: :forbidden}} =
               UnifiApi.Network.Devices.list(client, "site-1")
    end

    test "Clients.list/2 surfaces RateLimitError on 429" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "30")
          |> Plug.Conn.send_resp(429, "{}")
        end)

      assert {:error, %UnifiApi.RateLimitError{retry_after: 30, status: 429}} =
               UnifiApi.Network.Clients.list(client, "site-1")
    end

    test "Networks.get/3 surfaces %ApiError{} on 404" do
      client = error_client(404, JSON.encode!(%{"error" => "not found"}))

      assert {:error, %UnifiApi.ApiError{status: 404, code: nil, body_preview: preview}} =
               UnifiApi.Network.Networks.get(client, "site-1", "net-1")

      # Body is scrubbed/truncated into a preview string, never the raw map.
      assert preview =~ "not found"
    end

    test "Devices.list/2 surfaces %ApiError{} on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "boom"}))

      assert {:error, %UnifiApi.ApiError{status: 500, code: nil, body_preview: preview}} =
               UnifiApi.Network.Devices.list(client, "site-1")

      # Body is scrubbed/truncated into a preview string, never the raw map.
      assert preview =~ "boom"
    end
  end

  # --- Assert-fn extension coverage ---

  describe "assert_request extension" do
    test "extra_assert can inspect query params" do
      client =
        assert_request("GET", "/v1/sites/site-1/devices", fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["limit"] == "50"
          assert params["offset"] == "100"
        end)

      assert {:ok, _} = UnifiApi.Network.Devices.list(client, "site-1", limit: 50, offset: 100)
    end

    test "extra_assert can inspect x-api-key header" do
      client =
        assert_request("GET", "/v1/sites", fn conn ->
          assert ["test-key"] = Plug.Conn.get_req_header(conn, "x-api-key")
        end)

      assert {:ok, _} = UnifiApi.Network.Sites.list(client)
    end

    test "assert_request_with_body extra_assert sees decoded JSON body" do
      client =
        assert_request_with_body("POST", "/v1/sites/site-1/devices", fn body ->
          assert body["mac"] == "aa:bb:cc:dd:ee:ff"
        end)

      assert {:ok, _} =
               UnifiApi.Network.Devices.adopt(client, "site-1", %{mac: "aa:bb:cc:dd:ee:ff"})
    end
  end

  # --- Path-segment boundary enforcement (CWE-22 / OWASP A03) ---
  #
  # `Client.validate_id!/1` is unit-tested at its definition site in
  # client_test.exs; these tests pin the *enforcement* sites, so dropping
  # the call from a resource module fails the suite instead of passing
  # silently. The plug flunks if it is ever invoked, which proves the
  # raise happens during path composition, before any request is issued.

  describe "resource-boundary id validation" do
    @traversal "../../admin"

    defp no_request_client do
      test_client(fn conn ->
        flunk("request was issued to #{conn.request_path} instead of raising")
      end)
    end

    test "Devices.get/3 rejects a traversal site id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Network.Devices.get(no_request_client(), @traversal, "dev-1")
      end
    end

    test "Devices.get/3 rejects a traversal device id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Network.Devices.get(no_request_client(), "site-1", @traversal)
      end
    end

    test "Networks.update/4 rejects a traversal network id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Network.Networks.update(no_request_client(), "site-1", @traversal, %{
          name: "lan"
        })
      end
    end

    test "Networks.delete/4 rejects a traversal site id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Network.Networks.delete(no_request_client(), @traversal, "net-1")
      end
    end

    test "ACL.delete/3 rejects a traversal rule id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Network.ACL.delete(no_request_client(), "site-1", @traversal)
      end
    end

    test "Devices.remove/3 rejects a non-binary device id" do
      assert_raise ArgumentError, fn ->
        UnifiApi.Network.Devices.remove(no_request_client(), "site-1", :dev_1)
      end
    end

    test "Devices.execute_port_action/5 rejects a string port index" do
      # Called through `apply/3`: a literal string here is exactly the
      # attack the guard blocks, but the compiler's type checker would
      # (correctly) warn about it at build time and the suite must stay
      # warning-free.
      args = [no_request_client(), "site-1", "dev-1", "1/../../../users", %{action: "cycle"}]

      assert_raise FunctionClauseError, fn ->
        apply(UnifiApi.Network.Devices, :execute_port_action, args)
      end
    end

    test "Devices.execute_port_action/5 rejects a negative port index" do
      assert_raise FunctionClauseError, fn ->
        UnifiApi.Network.Devices.execute_port_action(
          no_request_client(),
          "site-1",
          "dev-1",
          -1,
          %{action: "cycle"}
        )
      end
    end
  end

  # --- Mutating-verb error paths ---
  #
  # Before v0.4.0 the suite had *no* non-2xx coverage on any
  # POST/PUT/DELETE: a mutating call returning a wrongly-shaped error
  # tuple shipped unnoticed. One test per umbrella member, spread across
  # verbs. `error_client/3` asserts the verb, so none of these can pass
  # against a GET issued by the wrong function.

  describe "mutating-verb error paths" do
    test "Networks.create/3 (POST) surfaces ApiError on 409" do
      client =
        error_client(409, JSON.encode!(%{"error" => "vlan already in use"}), method: "POST")

      assert {:error, %UnifiApi.ApiError{status: 409, body_preview: preview}} =
               UnifiApi.Network.Networks.create(client, "site-1", %{name: "Guest"})

      assert preview =~ "vlan already in use"
    end

    test "ACL.create/3 (POST) surfaces AuthError on 401" do
      client = error_client(401, JSON.encode!(%{"error" => "bad key"}), method: "POST")

      assert {:error, %UnifiApi.AuthError{status: 401, reason: :unauthorized}} =
               UnifiApi.Network.ACL.create(client, "site-1", %{name: "block-guest"})
    end

    test "DNS.create/3 (POST) surfaces ApiError on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "boom"}), method: "POST")

      assert {:error, %UnifiApi.ApiError{status: 500}} =
               UnifiApi.Network.DNS.create(client, "site-1", %{name: "block-ads"})
    end

    test "Devices.execute_action/4 (POST) clamps an absurd Retry-After to 300s on 429" do
      client = error_client(429, "{}", method: "POST", headers: [{"retry-after", "99999"}])

      assert {:error, %UnifiApi.RateLimitError{status: 429, retry_after: 300}} =
               UnifiApi.Network.Devices.execute_action(client, "site-1", "dev-1", %{
                 action: "restart"
               })
    end

    test "Networks.update/4 (PUT) surfaces AuthError on 403" do
      client = error_client(403, JSON.encode!(%{"error" => "read-only admin"}), method: "PUT")

      assert {:error, %UnifiApi.AuthError{status: 403, reason: :forbidden}} =
               UnifiApi.Network.Networks.update(client, "site-1", "net-1", %{name: "LAN"})
    end

    test "Firewall.update_policy/4 (PUT) surfaces RateLimitError with parsed Retry-After on 429" do
      client = error_client(429, "{}", method: "PUT", headers: [{"retry-after", "30"}])

      assert {:error, %UnifiApi.RateLimitError{status: 429, retry_after: 30}} =
               UnifiApi.Network.Firewall.update_policy(client, "site-1", "pol-1", %{
                 enabled: false
               })
    end

    test "PortForward.update/4 (PUT) surfaces ApiError on 409" do
      client = error_client(409, JSON.encode!(%{"error" => "port 443 taken"}), method: "PUT")

      assert {:error, %UnifiApi.ApiError{status: 409}} =
               UnifiApi.Network.PortForward.update(client, "site-1", "fwd-1", %{fwdPort: 443})
    end

    test "Networks.delete/3 (DELETE) surfaces ApiError on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "boom"}), method: "DELETE")

      assert {:error, %UnifiApi.ApiError{status: 500}} =
               UnifiApi.Network.Networks.delete(client, "site-1", "net-1")
    end

    test "Devices.remove/3 (DELETE) surfaces AuthError on 401" do
      client = error_client(401, JSON.encode!(%{"error" => "expired session"}), method: "DELETE")

      assert {:error, %UnifiApi.AuthError{status: 401, reason: :unauthorized}} =
               UnifiApi.Network.Devices.remove(client, "site-1", "dev-1")
    end

    test "Firewall.delete_zone/3 (DELETE) surfaces AuthError on 403" do
      client = error_client(403, JSON.encode!(%{"error" => "zone is locked"}), method: "DELETE")

      assert {:error, %UnifiApi.AuthError{status: 403, reason: :forbidden}} =
               UnifiApi.Network.Firewall.delete_zone(client, "site-1", "zone-1")
    end

    # The remaining umbrella member reachable from a mutating verb.
    # `Client.post/4`'s own wrapping is unit-tested in
    # transport_error_test.exs; this pins that a *resource* module does not
    # unwrap or reshape it on the way back out.
    test "Devices.adopt/3 (POST) wraps a transport failure in TransportError" do
      client = test_client(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error,
              %UnifiApi.TransportError{
                reason: :econnrefused,
                original: %Req.TransportError{reason: :econnrefused}
              }} = UnifiApi.Network.Devices.adopt(client, "site-1", %{mac: "aa:bb:cc"})
    end

    # CWE-209: a controller error body can echo internal infrastructure.
    # `Client.scrub_body_preview/1` runs on the ApiError path too, so the
    # preview must never carry the URL verbatim.
    test "Networks.create/3 scrubs a leaked URL out of ApiError body_preview" do
      leaked = "https://internal.example.com/secret"

      client =
        error_client(
          409,
          JSON.encode!(%{"error" => "conflict", "detail" => "see #{leaked}"}),
          method: "POST"
        )

      assert {:error, %UnifiApi.ApiError{status: 409, body_preview: preview}} =
               UnifiApi.Network.Networks.create(client, "site-1", %{name: "Guest"})

      refute preview =~ leaked
      refute preview =~ "internal.example.com"
      assert preview =~ "[url]"
    end
  end

  # --- Module error-path coverage ---
  #
  # Read surfaces consumers actually call that had zero error-path
  # coverage before v0.4.0: Wifi, Firewall, ACL, DNS, PortForward, Info.
  # `Sites.find_by_name/2` is here because it is the one function that
  # returns a bare atom on a *miss* — the test below pins that a transport
  # of an HTTP failure still comes back as an umbrella struct, not
  # `:not_found`.

  describe "module error-path coverage" do
    test "Info.get_info/1 surfaces ApiError on 503" do
      client = error_client(503, JSON.encode!(%{"error" => "upgrading"}))

      assert {:error, %UnifiApi.ApiError{status: 503}} =
               UnifiApi.Network.Info.get_info(client)
    end

    test "Wifi.list/2 surfaces ApiError on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "boom"}), method: "GET")

      assert {:error, %UnifiApi.ApiError{status: 500}} =
               UnifiApi.Network.Wifi.list(client, "site-1")
    end

    test "Firewall.list_zones/2 surfaces AuthError on 403" do
      client = error_client(403, JSON.encode!(%{"error" => "no access"}))

      assert {:error, %UnifiApi.AuthError{status: 403, reason: :forbidden}} =
               UnifiApi.Network.Firewall.list_zones(client, "site-1")
    end

    test "ACL.list/2 surfaces RateLimitError on 429" do
      client = error_client(429, "{}", headers: [{"retry-after", "12"}])

      assert {:error, %UnifiApi.RateLimitError{status: 429, retry_after: 12}} =
               UnifiApi.Network.ACL.list(client, "site-1")
    end

    test "DNS.list/2 surfaces AuthError on 401" do
      client = error_client(401, JSON.encode!(%{"error" => "bad key"}))

      assert {:error, %UnifiApi.AuthError{status: 401, reason: :unauthorized}} =
               UnifiApi.Network.DNS.list(client, "site-1")
    end

    test "PortForward.list/2 surfaces ApiError on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "boom"}))

      assert {:error, %UnifiApi.ApiError{status: 500}} =
               UnifiApi.Network.PortForward.list(client, "site-1")
    end

    test "Sites.find_by_name/2 propagates ApiError instead of :not_found on 500" do
      client = error_client(500, JSON.encode!(%{"error" => "boom"}))

      assert {:error, %UnifiApi.ApiError{status: 500}} =
               UnifiApi.Network.Sites.find_by_name(client, "HQ")
    end
  end
end
