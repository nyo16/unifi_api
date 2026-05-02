defmodule UnifiApi.Network.TrafficTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.Traffic

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "by_client/3 hits /v2/api/site/{site}/traffic with start/end/interval" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/traffic"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["start"] == "1700000000000"
        assert params["interval"] == "hour"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} =
             Traffic.by_client(client, "default", start: 1_700_000_000_000, interval: "hour")
  end

  test "by_country/3 hits /country-traffic" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/country-traffic"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = Traffic.by_country(client, "default")
  end
end
