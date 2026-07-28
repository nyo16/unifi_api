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
end
