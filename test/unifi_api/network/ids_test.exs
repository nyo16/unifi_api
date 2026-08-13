defmodule UnifiApi.Network.IDSTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.IDS

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/3 hits /stat/ips/event with v1 paging params" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/ips/event"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["within"] == "12"
        assert params["_limit"] == "50"
        assert params["_start"] == "0"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"_id" => "i1", "key" => "EVT_IPS_IpsAlert"}]
        })
      end)

    assert {:ok, [%{"key" => "EVT_IPS_IpsAlert"}]} =
             IDS.list(client, "default", within_hours: 12, limit: 50, start: 0)
  end

  test "stream/3 auto-paginates IDS events via _start/_limit" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/ips/event"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["_limit"] == "2"

        # A full page (== _limit) keeps the stream going; the short
        # second page terminates it.
        data =
          case params["_start"] do
            "0" -> [%{"_id" => "i1"}, %{"_id" => "i2"}]
            "2" -> [%{"_id" => "i3"}]
          end

        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => data})
      end)

    assert IDS.stream(client, "default", limit: 2) |> Enum.to_list() ==
             [%{"_id" => "i1"}, %{"_id" => "i2"}, %{"_id" => "i3"}]
  end

  test "stream/3 forwards :within_hours as within= and defaults _limit to 500" do
    client =
      test_client(fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["within"] == "24"
        assert params["_limit"] == "500"
        assert params["_start"] == "0"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"_id" => "i9", "key" => "EVT_IPS_IpsAlert"}]
        })
      end)

    assert IDS.stream(client, "default", within_hours: 24) |> Enum.to_list() ==
             [%{"_id" => "i9", "key" => "EVT_IPS_IpsAlert"}]
  end
end
