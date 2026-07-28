defmodule UnifiApi.Network.WANTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.WAN

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "enriched_config/2 hits /v2/api/site/{site}/wan/enriched-configuration" do
    client =
      test_client(fn conn ->
        assert conn.request_path ==
                 "/proxy/network/v2/api/site/default/wan/enriched-configuration"

        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = WAN.enriched_config(client, "default")
  end

  test "isp_status/3 hits /wan/{wan_id}/isp-status" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/wan/wan1/isp-status"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => %{"up" => true}})
      end)

    assert {:ok, %{"up" => true}} = WAN.isp_status(client, "default", "wan1")
  end

  test "load_balancing/2 hits /wan/load-balancing" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/wan/load-balancing"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => %{}})
      end)

    assert {:ok, %{}} = WAN.load_balancing(client, "default")
  end

  test "slas/2 hits /wan-slas" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/wan-slas"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = WAN.slas(client, "default")
  end
end
