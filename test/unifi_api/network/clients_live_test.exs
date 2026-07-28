defmodule UnifiApi.Network.ClientsLiveTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.ClientsLive

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/2 hits /stat/sta and unwraps data" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/sta"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [
            %{
              "_id" => "c1",
              "mac" => "aa:bb:cc:dd:ee:ff",
              "signal" => -55,
              "noise" => -95,
              "satisfaction" => 92,
              "is_wired" => false
            }
          ]
        })
      end)

    assert {:ok, [%{"signal" => -55, "satisfaction" => 92}]} = ClientsLive.list(client, "default")
  end

  test "list_all/3 hits /stat/alluser and forwards :within_hours" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/alluser"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["within"] == "168"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = ClientsLive.list_all(client, "default", within_hours: 168)
  end
end
