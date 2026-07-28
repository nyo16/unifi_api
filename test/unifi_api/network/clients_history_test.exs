defmodule UnifiApi.Network.ClientsHistoryTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.ClientsHistory

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/3 hits /v2/api/site/{site}/clients/history with v2 paging params" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/clients/history"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["withinHours"] == "168"
        assert params["type"] == "WIRELESS"
        assert params["searchString"] == "iphone"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} =
             ClientsHistory.list(client, "default",
               within_hours: 168,
               type: "WIRELESS",
               search: "iphone"
             )
  end
end
