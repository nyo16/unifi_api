defmodule UnifiApi.Network.TopologyTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.Topology

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "get/2 hits /v2/api/site/{site}/topology" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/topology"

        Req.Test.json(conn, [
          %{"id" => "n1", "type" => "gateway", "name" => "UDM", "parent" => nil},
          %{"id" => "n2", "type" => "switch", "name" => "USW", "parent" => "n1"}
        ])
      end)

    assert {:ok, [%{"type" => "gateway"}, %{"type" => "switch"}]} =
             Topology.get(client, "default")
  end
end
