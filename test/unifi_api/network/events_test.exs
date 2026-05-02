defmodule UnifiApi.Network.EventsTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.Events

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/3 hits /proxy/network/api/s/{site}/stat/event and unwraps data" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/event"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [
            %{"_id" => "e1", "key" => "EVT_AP_Connected", "subsystem" => "wlan"},
            %{"_id" => "e2", "key" => "EVT_LU_Disconnected", "subsystem" => "lan"}
          ]
        })
      end)

    assert {:ok, [%{"_id" => "e1"}, %{"_id" => "e2"}]} = Events.list(client, "default")
  end

  test "list/3 forwards within_hours, limit, start as v1 query params" do
    client =
      test_client(fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["within"] == "24"
        assert params["_limit"] == "100"
        assert params["_start"] == "0"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = Events.list(client, "default", within_hours: 24, limit: 100, start: 0)
  end

  test "list/3 surfaces meta.rc == error" do
    client =
      test_client(fn conn ->
        Req.Test.json(conn, %{"meta" => %{"rc" => "error", "msg" => "api.err.LoginRequired"}})
      end)

    assert {:error, {:unifi_error, "api.err.LoginRequired"}} = Events.list(client, "default")
  end
end
