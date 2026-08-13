defmodule UnifiApi.Network.PortForwardTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.PortForward

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/2 hits /rest/portforward" do
    client =
      test_client(fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/proxy/network/api/s/default/rest/portforward"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"_id" => "r1", "name" => "Game"}]
        })
      end)

    assert {:ok, [%{"name" => "Game"}]} = PortForward.list(client, "default")
  end

  test "list/3 forwards :limit and :start as the v1 _limit/_start params" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/rest/portforward"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["_limit"] == "100"
        assert params["_start"] == "0"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = PortForward.list(client, "default", limit: 100, start: 0)
  end

  test "list/3 rejects an unknown option instead of dropping it" do
    client = test_client(fn conn -> Req.Test.json(conn, %{}) end)

    assert_raise ArgumentError, fn -> PortForward.list(client, "default", offset: 10) end
  end

  test "get/3 hits /rest/portforward/{rule_id}" do
    client =
      test_client(fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/proxy/network/api/s/default/rest/portforward/r1"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"_id" => "r1", "name" => "Game", "dst_port" => "25565"}]
        })
      end)

    assert {:ok, [%{"_id" => "r1", "dst_port" => "25565"}]} =
             PortForward.get(client, "default", "r1")
  end

  test "get/3 rejects a traversal-shaped rule id" do
    assert_raise ArgumentError, fn ->
      PortForward.get(test_client(fn conn -> conn end), "default", "../../users")
    end
  end

  test "create/3 POSTs body" do
    client =
      test_client(fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/proxy/network/api/s/default/rest/portforward"

        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        assert JSON.decode!(raw)["name"] == "Game"

        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, _} = PortForward.create(client, "default", %{name: "Game", proto: "tcp"})
  end

  test "update/4 PUTs the body to /rest/portforward/{rule_id}" do
    client =
      test_client(fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/proxy/network/api/s/default/rest/portforward/r1"

        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        body = JSON.decode!(raw)
        assert body["enabled"] == false
        assert body["fwd_port"] == "8080"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"_id" => "r1", "enabled" => false}]
        })
      end)

    # Writes go through the generic `Client.put/4`, which — unlike
    # `Client.get_v1/3` — does not unwrap the v1 `meta`/`data` envelope,
    # so callers see the raw body.
    assert {:ok, %{"data" => [%{"_id" => "r1", "enabled" => false}], "meta" => %{"rc" => "ok"}}} =
             PortForward.update(client, "default", "r1", %{enabled: false, fwd_port: "8080"})
  end

  test "delete/3 DELETEs the rule" do
    client =
      test_client(fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/proxy/network/api/s/default/rest/portforward/r1"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, _} = PortForward.delete(client, "default", "r1")
  end
end
