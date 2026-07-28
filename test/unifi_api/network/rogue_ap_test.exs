defmodule UnifiApi.Network.RogueAPTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.RogueAP

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/2 hits /stat/rogueap" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/rogueap"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => [%{"bssid" => "ab:cd"}]})
      end)

    assert {:ok, [%{"bssid" => "ab:cd"}]} = RogueAP.list(client, "default")
  end

  test "list_known/2 hits /rest/rogueknown" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/rest/rogueknown"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = RogueAP.list_known(client, "default")
  end
end
