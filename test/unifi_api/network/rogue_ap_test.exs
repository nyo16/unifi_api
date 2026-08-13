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

  test "list/3 forwards :limit and :start as the v1 _limit/_start params" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/rogueap"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["_limit"] == "200"
        assert params["_start"] == "400"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = RogueAP.list(client, "default", limit: 200, start: 400)
  end

  test "list/3 rejects an unknown option instead of dropping it" do
    client = test_client(fn conn -> Req.Test.json(conn, %{}) end)

    assert_raise ArgumentError, fn -> RogueAP.list(client, "default", max_items: 10) end
  end

  test "list_known/2 hits /rest/rogueknown" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/rest/rogueknown"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = RogueAP.list_known(client, "default")
  end

  test "list_known/3 forwards paging params too" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/rest/rogueknown"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["_limit"] == "25"
        assert params["_start"] == "0"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = RogueAP.list_known(client, "default", limit: 25, start: 0)
  end
end
