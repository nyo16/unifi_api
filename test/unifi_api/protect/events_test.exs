defmodule UnifiApi.Protect.EventsTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Protect.Events

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/2 hits /proxy/protect/api/events with filters" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/protect/api/events"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["start"] == "1700000000000"
        assert params["types"] == "motion,smartDetectZone"
        assert params["cameras"] == "cam-1,cam-2"
        Req.Test.json(conn, [%{"id" => "ev-1", "type" => "motion"}])
      end)

    assert {:ok, [%{"type" => "motion"}]} =
             Events.list(client,
               start: 1_700_000_000_000,
               types: ["motion", "smartDetectZone"],
               cameras: ["cam-1", "cam-2"]
             )
  end

  test "get/2 hits /api/events/{id}" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/protect/api/events/ev-1"
        Req.Test.json(conn, %{"id" => "ev-1"})
      end)

    assert {:ok, %{"id" => "ev-1"}} = Events.get(client, "ev-1")
  end

  test "thumbnail/3 returns binary JPEG via get_raw" do
    jpeg = <<0xFF, 0xD8, 0xFF, 0x00, 0x01, 0x02>>

    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/protect/api/events/ev-1/thumbnail"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["w"] == "640"

        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.send_resp(200, jpeg)
      end)

    assert {:ok, ^jpeg} = Events.thumbnail(client, "ev-1", width: 640)
  end

  test "system_logs/1 hits /api/events/system-logs" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/protect/api/events/system-logs"
        Req.Test.json(conn, [])
      end)

    assert {:ok, []} = Events.system_logs(client)
  end
end
