defmodule UnifiApi.Network.IDSTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.IDS

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/3 hits /stat/ips/event with v1 paging params" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/ips/event"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["within"] == "12"
        assert params["_limit"] == "50"
        assert params["_start"] == "0"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"_id" => "i1", "key" => "EVT_IPS_IpsAlert"}]
        })
      end)

    assert {:ok, [%{"key" => "EVT_IPS_IpsAlert"}]} =
             IDS.list(client, "default", within_hours: 12, limit: 50, start: 0)
  end
end
