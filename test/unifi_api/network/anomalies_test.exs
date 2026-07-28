defmodule UnifiApi.Network.AnomaliesTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.Anomalies

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/3 hits /stat/anomalies and forwards :within_hours" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/anomalies"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["within"] == "24"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"_id" => "a1", "anomaly" => "poor_signal"}]
        })
      end)

    assert {:ok, [%{"anomaly" => "poor_signal"}]} =
             Anomalies.list(client, "default", within_hours: 24)
  end
end
