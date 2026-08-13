defmodule UnifiApi.Network.PortAnomaliesTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.PortAnomalies

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/2 hits /v2/api/site/{site}/ports/port-anomalies" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/ports/port-anomalies"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = PortAnomalies.list(client, "default")
  end

  test "list/3 forwards :params verbatim (the v2 paging escape hatch)" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/ports/port-anomalies"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["pageSize"] == "500"
        assert params["pageNumber"] == "1"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} =
             PortAnomalies.list(client, "default", params: [pageSize: 500, pageNumber: 1])
  end

  test "list/3 rejects :offset rather than sending a param the handler ignores" do
    client = test_client(fn conn -> Req.Test.json(conn, %{}) end)

    assert_raise ArgumentError, fn -> PortAnomalies.list(client, "default", offset: 1) end
  end
end
