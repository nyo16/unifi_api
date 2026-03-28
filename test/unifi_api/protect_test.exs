defmodule UnifiApi.ProtectTest do
  use ExUnit.Case, async: true

  defp test_client(plug) do
    Req.new(
      base_url: "http://localhost",
      headers: [{"x-api-key", "test-key"}],
      plug: plug
    )
  end

  defp assert_request(method, path) do
    test_client(fn conn ->
      assert conn.method == method
      assert conn.request_path == "/proxy/protect/integration#{path}"
      Req.Test.json(conn, %{"ok" => true})
    end)
  end

  defp assert_request_with_body(method, path) do
    test_client(fn conn ->
      assert conn.method == method
      assert conn.request_path == "/proxy/protect/integration#{path}"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = JSON.decode!(raw)
      Req.Test.json(conn, %{"ok" => true, "body" => body})
    end)
  end

  # --- Cameras ---

  describe "Cameras" do
    test "list/1" do
      client = assert_request("GET", "/v1/cameras")
      assert {:ok, _} = UnifiApi.Protect.Cameras.list(client)
    end

    test "get/2" do
      client = assert_request("GET", "/v1/cameras/cam-1")
      assert {:ok, _} = UnifiApi.Protect.Cameras.get(client, "cam-1")
    end

    test "update/3" do
      client = assert_request_with_body("PATCH", "/v1/cameras/cam-1")

      assert {:ok, %{"body" => %{"name" => "Front Door"}}} =
               UnifiApi.Protect.Cameras.update(client, "cam-1", %{name: "Front Door"})
    end

    test "snapshot/3 returns raw binary" do
      client =
        test_client(fn conn ->
          assert conn.method == "GET"
          assert conn.request_path == "/proxy/protect/integration/v1/cameras/cam-1/snapshot"

          conn
          |> Plug.Conn.put_resp_content_type("image/jpeg")
          |> Plug.Conn.send_resp(200, <<0xFF, 0xD8, 0xFF>>)
        end)

      assert {:ok, <<0xFF, 0xD8, 0xFF>>} = UnifiApi.Protect.Cameras.snapshot(client, "cam-1")
    end

    test "snapshot/3 passes highQuality param" do
      client =
        test_client(fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["highQuality"] == "true"

          conn
          |> Plug.Conn.put_resp_content_type("image/jpeg")
          |> Plug.Conn.send_resp(200, <<0xFF>>)
        end)

      assert {:ok, _} = UnifiApi.Protect.Cameras.snapshot(client, "cam-1", high_quality: true)
    end

    test "ptz_patrol_start/3" do
      client = assert_request_with_body("POST", "/v1/cameras/cam-1/ptz/patrol/start/2")

      assert {:ok, _} = UnifiApi.Protect.Cameras.ptz_patrol_start(client, "cam-1", 2)
    end

    test "ptz_patrol_stop/2" do
      client = assert_request_with_body("POST", "/v1/cameras/cam-1/ptz/patrol/stop")

      assert {:ok, _} = UnifiApi.Protect.Cameras.ptz_patrol_stop(client, "cam-1")
    end

    test "ptz_goto/3" do
      client = assert_request_with_body("POST", "/v1/cameras/cam-1/ptz/goto/5")

      assert {:ok, _} = UnifiApi.Protect.Cameras.ptz_goto(client, "cam-1", 5)
    end
  end

  # --- NVR ---

  describe "NVR" do
    test "get/1" do
      client = assert_request("GET", "/v1/nvrs")
      assert {:ok, _} = UnifiApi.Protect.NVR.get(client)
    end
  end

  # --- Viewers ---

  describe "Viewers" do
    test "list/1" do
      client = assert_request("GET", "/v1/viewers")
      assert {:ok, _} = UnifiApi.Protect.Viewers.list(client)
    end

    test "get/2" do
      client = assert_request("GET", "/v1/viewers/v1")
      assert {:ok, _} = UnifiApi.Protect.Viewers.get(client, "v1")
    end

    test "update/3" do
      client = assert_request_with_body("PATCH", "/v1/viewers/v1")

      assert {:ok, %{"body" => %{"liveview" => "lv-1"}}} =
               UnifiApi.Protect.Viewers.update(client, "v1", %{liveview: "lv-1"})
    end
  end

  # --- Liveviews ---

  describe "Liveviews" do
    test "list/1" do
      client = assert_request("GET", "/v1/liveviews")
      assert {:ok, _} = UnifiApi.Protect.Liveviews.list(client)
    end

    test "get/2" do
      client = assert_request("GET", "/v1/liveviews/lv-1")
      assert {:ok, _} = UnifiApi.Protect.Liveviews.get(client, "lv-1")
    end
  end

  # --- Sensors ---

  describe "Sensors" do
    test "list/1" do
      client = assert_request("GET", "/v1/sensors")
      assert {:ok, _} = UnifiApi.Protect.Sensors.list(client)
    end

    test "get/2" do
      client = assert_request("GET", "/v1/sensors/sensor-1")
      assert {:ok, _} = UnifiApi.Protect.Sensors.get(client, "sensor-1")
    end

    test "update/3" do
      client = assert_request_with_body("PATCH", "/v1/sensors/sensor-1")

      assert {:ok, %{"body" => %{"name" => "Door Sensor"}}} =
               UnifiApi.Protect.Sensors.update(client, "sensor-1", %{name: "Door Sensor"})
    end
  end

  # --- Lights ---

  describe "Lights" do
    test "list/1" do
      client = assert_request("GET", "/v1/lights")
      assert {:ok, _} = UnifiApi.Protect.Lights.list(client)
    end

    test "get/2" do
      client = assert_request("GET", "/v1/lights/light-1")
      assert {:ok, _} = UnifiApi.Protect.Lights.get(client, "light-1")
    end

    test "update/3" do
      client = assert_request_with_body("PATCH", "/v1/lights/light-1")

      assert {:ok, %{"body" => %{"name" => "Porch Light"}}} =
               UnifiApi.Protect.Lights.update(client, "light-1", %{name: "Porch Light"})
    end
  end

  # --- Chimes ---

  describe "Chimes" do
    test "list/1" do
      client = assert_request("GET", "/v1/chimes")
      assert {:ok, _} = UnifiApi.Protect.Chimes.list(client)
    end

    test "get/2" do
      client = assert_request("GET", "/v1/chimes/chime-1")
      assert {:ok, _} = UnifiApi.Protect.Chimes.get(client, "chime-1")
    end

    test "update/3" do
      client = assert_request_with_body("PATCH", "/v1/chimes/chime-1")

      assert {:ok, %{"body" => %{"volume" => 80}}} =
               UnifiApi.Protect.Chimes.update(client, "chime-1", %{volume: 80})
    end
  end

  # --- Protect Streams ---

  describe "Protect Streams" do
    defp stream_client(path) do
      page_count = :counters.new(1, [:atomics])

      test_client(fn conn ->
        assert conn.request_path == "/proxy/protect/integration#{path}"
        :counters.add(page_count, 1, 1)
        params = Plug.Conn.fetch_query_params(conn).query_params
        offset = String.to_integer(params["offset"] || "0")

        items =
          if offset == 0,
            do: [%{"id" => "a"}, %{"id" => "b"}],
            else: [%{"id" => "c"}]

        Req.Test.json(conn, items)
      end)
    end

    test "Sensors.stream/1" do
      client = stream_client("/v1/sensors")
      result = UnifiApi.Protect.Sensors.stream(client, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Lights.stream/1" do
      client = stream_client("/v1/lights")
      result = UnifiApi.Protect.Lights.stream(client, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Chimes.stream/1" do
      client = stream_client("/v1/chimes")
      result = UnifiApi.Protect.Chimes.stream(client, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end

    test "Liveviews.stream/1" do
      client = stream_client("/v1/liveviews")
      result = UnifiApi.Protect.Liveviews.stream(client, limit: 2) |> Enum.to_list()
      assert length(result) == 3
    end
  end
end
