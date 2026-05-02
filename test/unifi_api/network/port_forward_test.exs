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
