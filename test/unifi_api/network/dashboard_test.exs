defmodule UnifiApi.Network.DashboardTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.Dashboard

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "get/3 hits /aggregated-dashboard with default historySeconds=3600" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/aggregated-dashboard"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["historySeconds"] == "3600"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => %{"clients" => 42}})
      end)

    assert {:ok, %{"clients" => 42}} = Dashboard.get(client, "default")
  end

  test "get/3 honours :history_seconds option" do
    client =
      test_client(fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["historySeconds"] == "604800"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => %{}})
      end)

    assert {:ok, %{}} = Dashboard.get(client, "default", history_seconds: 604_800)
  end
end
