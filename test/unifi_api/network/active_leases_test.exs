defmodule UnifiApi.Network.ActiveLeasesTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.ActiveLeases

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/2 hits /v2/api/site/{site}/active-leases" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/active-leases"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => [%{"mac" => "aa:bb"}]})
      end)

    assert {:ok, [%{"mac" => "aa:bb"}]} = ActiveLeases.list(client, "default")
  end
end
