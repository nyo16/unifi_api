defmodule UnifiApi.Network.SystemLogTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.SystemLog

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list_all/3 hits /v2/api/site/{site}/system-log/all with paging" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/system-log/all"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["pageSize"] == "100"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = SystemLog.list_all(client, "default", limit: 100)
  end
end
