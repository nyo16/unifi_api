defmodule UnifiApi.Auth.SessionTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Auth.Session

  defp make_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  defp counter_plug(state_pid, fun) do
    fn conn ->
      n = Agent.get_and_update(state_pid, fn n -> {n, n + 1} end)
      fun.(conn, n)
    end
  end

  describe "start_link/1" do
    test "logs in synchronously and stores the authed request" do
      base =
        make_client(fn conn ->
          assert conn.request_path == "/api/auth/login"

          conn
          |> Plug.Conn.put_resp_header("x-csrf-token", "tok-1")
          |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=abc; Path=/"}])
          |> Plug.Conn.send_resp(200, "{}")
        end)

      {:ok, session} =
        Session.start_link(client: base, username: "admin", password: "secret", style: :udm)

      assert Session.csrf_token(session) == "tok-1"
    end

    test "stops with the AuthError when credentials are rejected" do
      base =
        make_client(fn conn -> Plug.Conn.send_resp(conn, 401, "{}") end)

      Process.flag(:trap_exit, true)

      assert {:error, %UnifiApi.AuthError{status: 401}} =
               Session.start_link(client: base, username: "admin", password: "wrong")
    end

    test "returns error when :client is missing" do
      Process.flag(:trap_exit, true)

      assert {:error, {%ArgumentError{message: msg}, _stack}} =
               Session.start_link(username: "u", password: "p")

      assert msg =~ ":client"
    end
  end

  describe "client/1" do
    test "returned request reads CURRENT auth state from the session" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      base =
        make_client(
          counter_plug(agent, fn conn, 0 ->
            assert conn.request_path == "/api/auth/login"

            conn
            |> Plug.Conn.put_resp_header("x-csrf-token", "tok-1")
            |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=abc; Path=/"}])
            |> Plug.Conn.send_resp(200, "{}")
          end)
        )

      {:ok, session} =
        Session.start_link(client: base, username: "admin", password: "secret")

      # Now swap in a plug that asserts on the headers + rotates CSRF
      authed_plug = fn conn ->
        # Each request should carry the latest CSRF
        token = Plug.Conn.get_req_header(conn, "x-csrf-token") |> List.first()
        cookie = Plug.Conn.get_req_header(conn, "cookie") |> List.first()
        send(self(), {:got_request, token, cookie})

        next_token =
          case token do
            "tok-1" -> "tok-2"
            "tok-2" -> "tok-3"
            _ -> "tok-x"
          end

        conn
        |> Plug.Conn.put_resp_header("x-csrf-token", next_token)
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ~s|{"meta":{"rc":"ok"},"data":[]}|)
      end

      authed = Session.client(session) |> Req.merge(plug: authed_plug)
      {:ok, _} = UnifiApi.Network.Events.list(authed, "default")
      # Wait for cast to be processed
      assert "tok-2" = Session.csrf_token(session)

      # Second call: rebind authed (same wrapping) and confirm tok-2 is sent
      authed2 = Session.client(session) |> Req.merge(plug: authed_plug)
      {:ok, _} = UnifiApi.Network.Events.list(authed2, "default")
      assert "tok-3" = Session.csrf_token(session)
    end

    test "handle_cast ignores empty x-csrf-token" do
      base =
        make_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-csrf-token", "tok-1")
          |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=abc; Path=/"}])
          |> Plug.Conn.send_resp(200, "{}")
        end)

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")

      authed_plug = fn conn ->
        # Don't set x-csrf-token at all
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ~s|{"meta":{"rc":"ok"},"data":[]}|)
      end

      authed = Session.client(session) |> Req.merge(plug: authed_plug)
      {:ok, _} = UnifiApi.Network.Events.list(authed, "default")
      assert "tok-1" = Session.csrf_token(session)
    end
  end

  describe "refresh/1" do
    test "issues a probe and updates the stored token" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      base =
        make_client(
          counter_plug(counter, fn
            conn, 0 ->
              # login
              conn
              |> Plug.Conn.put_resp_header("x-csrf-token", "tok-original")
              |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=abc; Path=/"}])
              |> Plug.Conn.send_resp(200, "{}")

            conn, 1 ->
              # refresh probe
              assert conn.request_path == "/"

              conn
              |> Plug.Conn.put_resp_header("x-csrf-token", "tok-refreshed")
              |> Plug.Conn.send_resp(200, "")
          end)
        )

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")
      assert "tok-original" = Session.csrf_token(session)

      assert :ok = Session.refresh(session)
      assert "tok-refreshed" = Session.csrf_token(session)
    end
  end

  describe "relogin/1" do
    test "re-runs the login flow and replaces the authed struct" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      base =
        make_client(
          counter_plug(counter, fn conn, n ->
            assert conn.request_path == "/api/auth/login"

            conn
            |> Plug.Conn.put_resp_header("x-csrf-token", "tok-#{n}")
            |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=cookie-#{n}; Path=/"}])
            |> Plug.Conn.send_resp(200, "{}")
          end)
        )

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")
      assert "tok-0" = Session.csrf_token(session)

      assert :ok = Session.relogin(session)
      assert "tok-1" = Session.csrf_token(session)
    end
  end
end
