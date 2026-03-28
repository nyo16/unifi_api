defmodule UnifiApi.NetworkTest do
  use ExUnit.Case, async: true

  defp test_client(plug) do
    Req.new(
      base_url: "http://localhost",
      headers: [{"x-api-key", "test-key"}],
      plug: plug
    )
  end

  defp assert_request(method, path) do
    test_client(fn conn ->
      assert conn.method == method
      assert conn.request_path == "/proxy/network/integration#{path}"
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

  defp assert_request_with_body(method, path) do
    test_client(fn conn ->
      assert conn.method == method
      assert conn.request_path == "/proxy/network/integration#{path}"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = JSON.decode!(raw)
      Req.Test.json(conn, %{"ok" => true, "body" => body})
    end)
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
  end
end
