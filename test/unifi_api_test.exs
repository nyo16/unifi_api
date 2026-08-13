defmodule UnifiApiTest do
  use ExUnit.Case, async: true

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  describe "new/0" do
    test "returns a Req.Request struct" do
      client = UnifiApi.new()
      assert %Req.Request{} = client
    end
  end

  describe "new/1" do
    test "accepts custom options" do
      client = UnifiApi.new(base_url: "https://10.0.0.1", api_key: "test-key")
      assert %Req.Request{} = client
    end
  end

  describe "detect/1" do
    test "returns :udm on 200" do
      client = test_client(fn conn -> Plug.Conn.send_resp(conn, 200, "<html>...</html>") end)

      assert {:ok,
              %{
                style: :udm,
                network_prefix: "/proxy/network/integration",
                protect_prefix: "/proxy/protect/integration",
                v1_prefix: "/proxy/network",
                auth_path: "/api/auth/login"
              }} = UnifiApi.detect(client)
    end

    test "returns :cloud_key on 302" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "/manage/account/login")
          |> Plug.Conn.send_resp(302, "")
        end)

      assert {:ok,
              %{
                style: :cloud_key,
                network_prefix: "/integration",
                protect_prefix: "/integration",
                v1_prefix: "",
                auth_path: "/api/login"
              }} = UnifiApi.detect(client)
    end

    test "returns :cloud_key on 301 and 303 too" do
      for status <- [301, 303] do
        client = test_client(fn conn -> Plug.Conn.send_resp(conn, status, "") end)
        assert {:ok, %{style: :cloud_key}} = UnifiApi.detect(client)
      end
    end

    test "does not follow redirects when probing" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "/login")
          |> Plug.Conn.send_resp(302, "")
        end)

      assert {:ok, %{style: :cloud_key}} = UnifiApi.detect(client)
    end

    test "returns %ApiError{} on other statuses" do
      client = test_client(fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      # Reconciled with ping/1: the identical case now yields the same struct.
      assert {:error, %UnifiApi.ApiError{status: 500}} = UnifiApi.detect(client)
    end

    # `detect/1` reaches the network through `Client.raw_get/2`, which
    # returns Req's own `{:error, %Req.TransportError{}}` unwrapped; the
    # wrapping is `detect/1`'s job. Broader per-entry-point transport
    # coverage lives in `test/unifi_api/transport_error_test.exs`.
    test "returns %TransportError{} when the controller is unreachable" do
      client = test_client(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error,
              %UnifiApi.TransportError{
                reason: :econnrefused,
                original: %Req.TransportError{reason: :econnrefused}
              }} = UnifiApi.detect(client)
    end
  end

  describe "ping/1" do
    test "returns :ok for 2xx" do
      client = test_client(fn conn -> Plug.Conn.send_resp(conn, 200, "") end)
      assert :ok = UnifiApi.ping(client)
    end

    test "returns :ok for 302 / 303 (Cloud Key style redirect)" do
      for status <- [301, 302, 303] do
        client = test_client(fn conn -> Plug.Conn.send_resp(conn, status, "") end)
        assert :ok = UnifiApi.ping(client)
      end
    end

    test "returns %ApiError{} for 4xx / 5xx" do
      client = test_client(fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)

      assert {:error, %UnifiApi.ApiError{status: 503, body_preview: preview}} =
               UnifiApi.ping(client)

      # Body is scrubbed/truncated into a preview string, never the raw body.
      assert preview =~ "down"
    end

    test "returns %TransportError{} when the probe times out" do
      client = test_client(fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error,
              %UnifiApi.TransportError{
                reason: :timeout,
                original: %Req.TransportError{reason: :timeout}
              }} = UnifiApi.ping(client)
    end
  end
end
