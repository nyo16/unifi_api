defmodule UnifiApi.Network.DPITest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.DPI

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "by_site/2 hits /stat/sitedpi" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/sitedpi"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => [%{"by_app" => []}]})
      end)

    assert {:ok, [%{"by_app" => []}]} = DPI.by_site(client, "default")
  end

  test "by_client/2 hits /stat/stadpi" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/stadpi"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => [%{"mac" => "ab:cd"}]})
      end)

    assert {:ok, [%{"mac" => "ab:cd"}]} = DPI.by_client(client, "default")
  end
end
