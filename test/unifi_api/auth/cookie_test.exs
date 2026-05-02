defmodule UnifiApi.Auth.CookieTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Auth.Cookie
  alias UnifiApi.AuthError

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  describe "login/4 — UDM style" do
    test "POSTs username/password to /api/auth/login" do
      client =
        test_client(fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/api/auth/login"

          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          assert JSON.decode!(raw) == %{"username" => "admin", "password" => "secret"}

          conn
          |> Plug.Conn.put_resp_header("x-csrf-token", "token-123")
          |> Plug.Conn.put_resp_header("set-cookie", "TOKEN=abc123; Path=/; HttpOnly")
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, JSON.encode!(%{"unique_id" => "user-1"}))
        end)

      assert {:ok, %Req.Request{} = authed} = Cookie.login(client, "admin", "secret")
      assert Req.Request.get_header(authed, "cookie") == ["TOKEN=abc123"]
      assert Req.Request.get_header(authed, "x-csrf-token") == ["token-123"]
      assert Cookie.csrf_token(authed) == "token-123"
    end

    test "merges multiple cookies into one Cookie header" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.prepend_resp_headers([
            {"set-cookie", "TOKEN=abc; Path=/"},
            {"set-cookie", "session=xyz; Path=/"}
          ])
          |> Plug.Conn.put_resp_header("x-csrf-token", "t")
          |> Plug.Conn.send_resp(200, "{}")
        end)

      assert {:ok, authed} = Cookie.login(client, "u", "p")
      [cookie] = Req.Request.get_header(authed, "cookie")
      assert cookie =~ "TOKEN=abc"
      assert cookie =~ "session=xyz"
    end
  end

  describe "login/4 — Cloud Key style" do
    test "POSTs to /api/login with remember flag" do
      client =
        test_client(fn conn ->
          assert conn.request_path == "/api/login"
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          body = JSON.decode!(raw)
          assert body == %{"username" => "u", "password" => "p", "remember" => false}

          conn
          |> Plug.Conn.prepend_resp_headers([
            {"set-cookie", "unifises=abc; Path=/"},
            {"set-cookie", "csrf_token=tok-456; Path=/"}
          ])
          |> Plug.Conn.send_resp(200, "{}")
        end)

      assert {:ok, authed} = Cookie.login(client, "u", "p", style: :cloud_key)
      assert Cookie.csrf_token(authed) == "tok-456"
      [cookie] = Req.Request.get_header(authed, "cookie")
      assert cookie =~ "unifises=abc"
      assert cookie =~ "csrf_token=tok-456"
    end

    test "honours :remember option" do
      client =
        test_client(fn conn ->
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          assert JSON.decode!(raw) |> Map.get("remember") == true
          Plug.Conn.send_resp(conn, 200, "{}")
        end)

      assert {:ok, _} = Cookie.login(client, "u", "p", style: :cloud_key, remember: true)
    end
  end

  describe "login/4 — error paths" do
    test "401 returns %AuthError{reason: :unauthorized}" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(401, JSON.encode!(%{"error" => "bad creds"}))
        end)

      assert {:error, %AuthError{status: 401, reason: :unauthorized}} =
               Cookie.login(client, "u", "wrong")
    end

    test "403 returns %AuthError{reason: :forbidden}" do
      client =
        test_client(fn conn ->
          Plug.Conn.send_resp(conn, 403, "{}")
        end)

      assert {:error, %AuthError{status: 403, reason: :forbidden}} =
               Cookie.login(client, "u", "p")
    end

    test "500 returns generic {:error, {status, body}}" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "boom"}))
        end)

      assert {:error, {500, %{"error" => "boom"}}} = Cookie.login(client, "u", "p")
    end
  end

  describe "refresh_csrf/2" do
    test "captures rotated CSRF from probe response" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-csrf-token", "rotated-789")
          |> Plug.Conn.send_resp(200, "")
        end)

      assert {:ok, refreshed} = Cookie.refresh_csrf(client)
      assert Cookie.csrf_token(refreshed) == "rotated-789"
      assert Req.Request.get_header(refreshed, "x-csrf-token") == ["rotated-789"]
    end

    test "returns the original client unchanged when probe has no CSRF" do
      client = test_client(fn conn -> Plug.Conn.send_resp(conn, 200, "") end)
      assert {:ok, ^client} = Cookie.refresh_csrf(client)
    end
  end

  describe "csrf_token/1" do
    test "returns nil when no token has been installed" do
      client = test_client(fn _ -> raise "unused" end)
      assert Cookie.csrf_token(client) == nil
    end
  end
end
