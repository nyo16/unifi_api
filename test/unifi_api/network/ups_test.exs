defmodule UnifiApi.Network.UPSTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.UPS

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/2 hits /stat/ups-devices" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/ups-devices"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"name" => "UPS1", "battery_charge" => 100}]
        })
      end)

    assert {:ok, [%{"battery_charge" => 100}]} = UPS.list(client, "default")
  end

  test "list/3 forwards :limit and :start as the v1 _limit/_start params" do
    client =
      test_client(fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["_limit"] == "50"
        assert params["_start"] == "50"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = UPS.list(client, "default", limit: 50, start: 50)
  end

  test "list/3 merges :params alongside the paging params" do
    client =
      test_client(fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["_limit"] == "10"
        assert params["ups_status"] == "OB"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = UPS.list(client, "default", limit: 10, params: [ups_status: "OB"])
  end

  test "list/3 rejects an unknown option instead of dropping it" do
    client = test_client(fn conn -> Req.Test.json(conn, %{}) end)

    assert_raise ArgumentError, fn -> UPS.list(client, "default", offset: 10) end
  end
end
