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

    test "returns {:error, {:unexpected_status, _, _}} on other statuses" do
      client = test_client(fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
      assert {:error, {:unexpected_status, 500, _}} = UnifiApi.detect(client)
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

    test "returns {:error, {status, body}} for 4xx / 5xx" do
      client = test_client(fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)
      assert {:error, {503, _}} = UnifiApi.ping(client)
    end
  end
end
