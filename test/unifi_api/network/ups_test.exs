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
end
