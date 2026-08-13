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

  describe "persistent_term snapshot (P2-T2 / P4-T3)" do
    test "csrf_token/1 reads from :persistent_term, no per-request call" do
      # Black-box check: concurrent readers can call csrf_token/1 without
      # serializing on the GenServer mailbox. We don't assert on the
      # per-session ref directly (it's private); we assert that the
      # snapshot rotation updates what every observer sees.
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      base =
        make_client(
          counter_plug(counter, fn conn, n ->
            conn
            |> Plug.Conn.put_resp_header("x-csrf-token", "tok-#{n}")
            |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=cookie-#{n}; Path=/"}])
            |> Plug.Conn.send_resp(200, "{}")
          end)
        )

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")
      assert "tok-0" = Session.csrf_token(session)

      assert :ok = Session.relogin(session)
      # The rotated snapshot replaces the old — readers see the new token
      # immediately, no mailbox roundtrip required.
      assert "tok-1" = Session.csrf_token(session)
    end

    test "rotation writes the new csrf back to the same snapshot slot" do
      # A response with a rotated x-csrf-token header should advance the
      # snapshot, so subsequent client() requests carry the rotated token.
      base =
        make_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-csrf-token", "tok-initial")
          |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=abc; Path=/"}])
          |> Plug.Conn.send_resp(200, "{}")
        end)

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")

      rotated_plug = fn conn ->
        next =
          conn
          |> Plug.Conn.get_req_header("x-csrf-token")
          |> List.first()
          |> case do
            "tok-initial" -> "tok-rotated"
            _ -> "tok-final"
          end

        conn
        |> Plug.Conn.put_resp_header("x-csrf-token", next)
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ~s|{"meta":{"rc":"ok"},"data":[]}|)
      end

      authed = Session.client(session) |> Req.merge(plug: rotated_plug)
      {:ok, _} = UnifiApi.Network.Events.list(authed, "default")

      # The capture_rotated_csrf cast writes the rotated token into the
      # persistent_term snapshot AND state.authed. csrf_token/1 reads
      # the snapshot directly.
      assert "tok-rotated" = Session.csrf_token(session)
    end

    test "two concurrent sessions do not clobber each other's snapshot" do
      # Each session's snapshot is keyed by a per-instance ref; multiple
      # sessions running side-by-side must not observe each other's CSRF.
      login = fn token ->
        make_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-csrf-token", token)
          |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=#{token}; Path=/"}])
          |> Plug.Conn.send_resp(200, "{}")
        end)
      end

      {:ok, s1} = Session.start_link(client: login.("s1-tok"), username: "u", password: "p")
      {:ok, s2} = Session.start_link(client: login.("s2-tok"), username: "u", password: "p")

      assert "s1-tok" = Session.csrf_token(s1)
      assert "s2-tok" = Session.csrf_token(s2)

      # After re-login of s1 only, s2's snapshot is untouched.
      assert :ok = Session.relogin(s2)
      # s1 untouched — its snapshot keyed by its own ref, not clobbered.
      assert "s1-tok" = Session.csrf_token(s1)
      # s2's plug returns the same token on each login call, so csrf stays.
      assert "s2-tok" = Session.csrf_token(s2)
    end
  end

  describe "wrapped client caching (P2-T2)" do
    test "client/1 returns the same struct on repeated calls (no per-call rebuild)" do
      base =
        make_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-csrf-token", "tok")
          |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=abc; Path=/"}])
          |> Plug.Conn.send_resp(200, "{}")
        end)

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")
      first = Session.client(session)
      second = Session.client(session)

      # Same identity — built once in init/1 and cached in state.wrapped.
      assert first == second
    end
  end

  describe ":relogin callback API (P2-T2)" do
    test "accepts a 0-arity callback instead of username/password" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      base =
        make_client(
          counter_plug(counter, fn conn, n ->
            conn
            |> Plug.Conn.put_resp_header("x-csrf-token", "tok-#{n}")
            |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=cookie-#{n}; Path=/"}])
            |> Plug.Conn.send_resp(200, "{}")
          end)
        )

      # Caller supplies a closure (no plaintext creds stored in state as
      # username/password fields). The closure captures external input
      # but the GenServer state does NOT carry separate username/password.
      relogin = fn ->
        UnifiApi.Auth.Cookie.login(base, "u", "p", style: :udm)
      end

      {:ok, session} = Session.start_link(client: base, relogin: relogin)
      assert "tok-0" = Session.csrf_token(session)

      assert :ok = Session.relogin(session)
      assert "tok-1" = Session.csrf_token(session)
    end

    test "raises if neither :relogin nor :username/:password is supplied" do
      Process.flag(:trap_exit, true)

      assert {:error, {%ArgumentError{message: msg}, _stack}} =
               Session.start_link(client: Req.new(base_url: "http://localhost"))

      assert msg =~ ":relogin"
      assert msg =~ ":username"
    end
  end

  describe "format_status/1 (CWE-209 / CWE-532)" do
    setup do
      base =
        make_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-csrf-token", "csrf-secret-token")
          |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=cookie-secret; Path=/"}])
          |> Plug.Conn.send_resp(200, "{}")
        end)

      {:ok, session} =
        Session.start_link(
          client: base,
          username: "admin",
          password: "pa55word-secret",
          style: :cloud_key,
          remember: true
        )

      %{session: session}
    end

    test "the raw state would leak credentials", %{session: session} do
      # Establishes that the redaction below is load-bearing rather than
      # decorative: this is what `:gen_server` logs by default on an
      # abnormal exit, and `handle_call({:relogin, _})` does network I/O, so
      # the crash path is reachable.
      raw = inspect(:sys.get_state(session), limit: :infinity, printable_limit: :infinity)

      assert raw =~ "cookie-secret"
      assert raw =~ "csrf-secret-token"
    end

    test "format_status/1 reports no credentials", %{session: session} do
      status = :sys.get_status(session)
      rendered = inspect(status, limit: :infinity, printable_limit: :infinity)

      refute rendered =~ "cookie-secret"
      refute rendered =~ "csrf-secret-token"
      refute rendered =~ "pa55word-secret"
      refute rendered =~ "admin"

      # Still useful for debugging.
      assert rendered =~ "cloud_key"
    end
  end

  describe "client/1 does not use the mailbox" do
    test "reads succeed while the session is blocked in a handle_call" do
      {:ok, gate} = Agent.start_link(fn -> :closed end)
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      base =
        make_client(
          counter_plug(agent, fn conn, n ->
            # Block every login *after* the initial one until released, to
            # simulate a slow controller during a re-login.
            if n > 0 do
              Enum.reduce_while(1..500, nil, fn _, _ ->
                if Agent.get(gate, & &1) == :open,
                  do: {:halt, nil},
                  else:
                    (
                      Process.sleep(2)
                      {:cont, nil}
                    )
              end)
            end

            conn
            |> Plug.Conn.put_resp_header("x-csrf-token", "tok-#{n}")
            |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=c#{n}; Path=/"}])
            |> Plug.Conn.send_resp(200, "{}")
          end)
        )

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")

      caller = self()
      spawn(fn -> send(caller, {:relogin, Session.relogin(session)}) end)

      # The session is now parked inside handle_call doing HTTP. A
      # `GenServer.call`-based `client/1` would queue behind it.
      assert %Req.Request{} = Session.client(session)
      assert Session.csrf_token(session) == "tok-0"

      Agent.update(gate, fn _ -> :open end)
      assert_receive {:relogin, :ok}, 5_000
    end

    test "exits with :noproc for a dead session" do
      assert catch_exit(Session.client(:no_such_unifi_session)) ==
               {:noproc, {Session, :client, [:no_such_unifi_session]}}
    end

    test "csrf_token/1 is nil for a dead session" do
      assert Session.csrf_token(:no_such_unifi_session) == nil
    end
  end

  describe "relogin/2 coalescing" do
    test "concurrent relogins after one expiry cause a single login" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      base =
        make_client(
          counter_plug(agent, fn conn, n ->
            conn
            |> Plug.Conn.put_resp_header("x-csrf-token", "tok-#{n}")
            |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=c#{n}; Path=/"}])
            |> Plug.Conn.send_resp(200, "{}")
          end)
        )

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")
      assert Agent.get(agent, & &1) == 1, "initial login"

      # Every consumer sees the same 401 at the same instant.
      observed_at = System.monotonic_time(:millisecond)
      Process.sleep(5)

      caller = self()

      for _ <- 1..10 do
        spawn(fn ->
          send(caller, {:done, GenServer.call(session, {:relogin, observed_at}, 5_000)})
        end)
      end

      for _ <- 1..10, do: assert_receive({:done, :ok}, 5_000)

      # Exactly one of the ten did the work; the rest were coalesced.
      assert Agent.get(agent, & &1) == 2
    end

    test "a relogin requested after the last login still logs in" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      base =
        make_client(
          counter_plug(agent, fn conn, n ->
            conn
            |> Plug.Conn.put_resp_header("x-csrf-token", "tok-#{n}")
            |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=c#{n}; Path=/"}])
            |> Plug.Conn.send_resp(200, "{}")
          end)
        )

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")

      Process.sleep(5)
      assert Session.relogin(session) == :ok
      assert Agent.get(agent, & &1) == 2

      Process.sleep(5)
      assert Session.relogin(session) == :ok
      assert Agent.get(agent, & &1) == 3
    end
  end

  describe "snapshot writes" do
    test "an echoed, unchanged csrf token does not rewrite persistent_term" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      base =
        make_client(
          counter_plug(agent, fn conn, n ->
            conn
            |> Plug.Conn.put_resp_header("x-csrf-token", "steady-token")
            |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=c#{n}; Path=/"}])
            |> Plug.Conn.send_resp(200, "{}")
          end)
        )

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")

      authed =
        Session.client(session)
        |> Req.merge(
          plug: fn conn ->
            conn
            |> Plug.Conn.put_resp_header("x-csrf-token", "steady-token")
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, ~s|{"meta":{"rc":"ok"},"data":[]}|)
          end
        )

      # Every `:persistent_term.put/2` triggers a global scan of every
      # process to find references to the replaced term (measured at 169µs
      # with 2000 live processes), and controllers echo this header on
      # essentially every response. A skipped write leaves the stored term
      # physically identical; a write copies it into the literal area.
      before_term = Session.client(session)

      for _ <- 1..20, do: {:ok, _} = UnifiApi.Network.Events.list(authed, "default")

      assert :erts_debug.same(before_term, Session.client(session)),
             "expected no persistent_term write for an unchanged token"

      assert Session.csrf_token(session) == "steady-token"
    end

    test "a changed csrf token does rewrite persistent_term" do
      # Control for the test above: proves the identity check can fail.
      base =
        make_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-csrf-token", "tok-initial")
          |> Plug.Conn.prepend_resp_headers([{"set-cookie", "TOKEN=abc; Path=/"}])
          |> Plug.Conn.send_resp(200, "{}")
        end)

      {:ok, session} = Session.start_link(client: base, username: "u", password: "p")

      authed =
        Session.client(session)
        |> Req.merge(
          plug: fn conn ->
            conn
            |> Plug.Conn.put_resp_header("x-csrf-token", "tok-rotated")
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, ~s|{"meta":{"rc":"ok"},"data":[]}|)
          end
        )

      before_term = Session.client(session)
      {:ok, _} = UnifiApi.Network.Events.list(authed, "default")

      refute :erts_debug.same(before_term, Session.client(session))
      assert Session.csrf_token(session) == "tok-rotated"
    end
  end
end
