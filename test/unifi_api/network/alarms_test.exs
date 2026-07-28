defmodule UnifiApi.Network.AlarmsTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.Alarms

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/3 hits /proxy/network/api/s/{site}/list/alarm" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/list/alarm"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"_id" => "a1", "archived" => false}]
        })
      end)

    assert {:ok, [%{"_id" => "a1"}]} = Alarms.list(client, "default")
  end

  test "list/3 forwards :archived filter" do
    client =
      test_client(fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["archived"] == "false"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = Alarms.list(client, "default", archived: false)
  end

  test "archive/3 POSTs to /cmd/evtmgr with archive-alarm cmd" do
    client =
      test_client(fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/proxy/network/api/s/default/cmd/evtmgr"

        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        body = JSON.decode!(raw)
        assert body == %{"cmd" => "archive-alarm", "_id" => "alarm-1"}

        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, _} = Alarms.archive(client, "default", "alarm-1")
  end
end
