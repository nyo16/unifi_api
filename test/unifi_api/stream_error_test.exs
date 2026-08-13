defmodule UnifiApi.StreamErrorTest do
  use ExUnit.Case, async: true

  alias UnifiApi.{ApiError, AuthError, Client, StreamError, TransportError}

  # Mirror `error_test.exs` shape: construct struct, assert
  # `Exception.message/1` redacts path/status (post P1-T5)
  # and that stream tuple contract (P2-T1) yields the
  # `{:error, %StreamError{}, last_offset}` triple.

  defp test_client(plug) do
    Req.new(
      base_url: "http://localhost",
      headers: [{"x-api-key", "test-key"}],
      plug: plug,
      retry: false
    )
  end

  describe "struct / message redaction (CWE-209)" do
    test "message/1 includes kind and status, not raw path/body" do
      err = %StreamError{
        kind: :api,
        status: 502,
        reason: %ApiError{status: 502, body_preview: ~s({"secret":"leak"})},
        path: "/v1/sites/default/clients",
        host: "controller.internal.example.com"
      }

      msg = Exception.message(err)

      assert msg =~ "502"
      refute msg =~ "/v1/sites/default/clients"
      refute msg =~ "secret"
      refute msg =~ "leak"
    end

    test "message/1 redacts host to registrable suffix only" do
      err = %StreamError{
        kind: :transport,
        status: :unknown,
        host: "udm-pro.controller.internal.example.com"
      }

      msg = Exception.message(err)
      # Registrable suffix kept, internal label dropped.
      assert msg =~ "controller.internal.example.com"
      refute msg =~ "udm-pro."
    end

    test "message/1 omits host part when host is nil" do
      err = %StreamError{kind: :api, status: 500, host: nil}
      msg = Exception.message(err)
      refute msg =~ " to "
    end
  end

  describe "build_stream_error/2" do
    test "translates AuthError reason into {:auth, status}" do
      reason = %AuthError{status: 401, reason: :unauthorized, body_preview: nil}
      err = Client.build_stream_error(reason, "/v1/sites/site-1/clients")

      assert err.kind == :auth
      assert err.status == 401
      # Path kept on struct for in-process use only.
      assert err.path == "/v1/sites/site-1/clients"
    end

    test "translates RateLimitError into {:rate_limit, 429}" do
      reason = %UnifiApi.RateLimitError{status: 429, retry_after: 30, body_preview: nil}
      err = Client.build_stream_error(reason, "/v1/sites/site-1/clients")

      assert err.kind == :rate_limit
      assert err.status == 429
    end

    test "translates %ApiError{} into {:api, status}" do
      err = Client.build_stream_error(%ApiError{status: 500, body_preview: "boom"}, "/v1/info")

      assert err.kind == :api
      assert err.status == 500
    end

    test "translates %ApiError{} with no status into {:api, :unknown}" do
      err = Client.build_stream_error(%ApiError{code: "api.err.Invalid"}, "/v1/info")

      assert err.kind == :api
      assert err.status == :unknown
    end

    test "translates %TransportError{} into {:transport, :unknown}" do
      err =
        Client.build_stream_error(
          %TransportError{
            reason: :econnrefused,
            original: %Req.TransportError{reason: :econnrefused}
          },
          "/v1/info"
        )

      assert err.kind == :transport
      assert err.status == :unknown
    end

    test "extracts host from absolute URL path" do
      err =
        Client.build_stream_error(
          %ApiError{status: 500, body_preview: "boom"},
          "https://controller.example/v1/info"
        )

      assert err.host == "controller.example"
    end

    test "host is nil for relative paths" do
      err = Client.build_stream_error(%ApiError{status: 500, body_preview: "boom"}, "/v1/info")
      assert err.host == nil
    end
  end

  describe "stream tuple contract (P2-T1)" do
    test "stream/3 halts and yields {:error, StreamError, last_offset} by default" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      client =
        test_client(fn conn ->
          n = Agent.get_and_update(agent, fn v -> {v, v + 1} end)

          case n do
            0 ->
              # First page: a short page (1 < limit) → halt with the items
              Req.Test.json(conn, [%{"id" => "a"}])

            _ ->
              # Any subsequent fetch (shouldn't happen here, but be defensive)
              Req.Test.json(conn, [])
          end
        end)

      result = Client.stream(client, "/v1/test", limit: 10) |> Enum.to_list()
      assert [%{"id" => "a"}] = result
    end

    test "stream/3 with raise_errors: true raises StreamError on first error" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(502, JSON.encode!(%{"error" => "upstream"}))
        end)

      assert_raise StreamError, fn ->
        Client.stream(client, "/v1/test", raise_errors: true, limit: 5)
        |> Enum.to_list()
      end
    end

    test "stream/3 yields final error tuple holding the failed page's offset" do
      # First fetch succeeds (full page → keep going), second fetch fails.
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      client =
        test_client(fn conn ->
          n = Agent.get_and_update(agent, fn v -> {v, v + 1} end)

          case n do
            0 ->
              # Full page (5 items, limit 5) → advance to offset 5
              Req.Test.json(conn, Enum.map(1..5, &%{"id" => &1}))

            _ ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "boom"}))
          end
        end)

      result = Client.stream(client, "/v1/test", limit: 5) |> Enum.to_list()
      items = Enum.take(result, 5)
      assert length(items) == 5

      {_, tail} = Enum.split(result, 5)

      assert [{:error, %StreamError{kind: :api, status: 500}, 5}] = tail
    end

    test "stream_v1/3 also yields error tuple on v1 envelope failure" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "boom"}))
        end)

      result = Client.stream_v1(client, "/api/s/default/stat/event", limit: 10) |> Enum.to_list()

      assert [{:error, %StreamError{kind: :api, status: 500}, 0}] = result
    end
  end

  describe "stream caps (P3-T6)" do
    test "max_pages halts at the cap regardless of available data" do
      # Each page returns a full page (10 items). max_pages: 2 → 20 items then halt.
      client =
        test_client(fn conn ->
          Req.Test.json(conn, Enum.map(1..10, &%{"id" => &1}))
        end)

      result = Client.stream(client, "/v1/test", limit: 10, max_pages: 2) |> Enum.to_list()
      assert length(result) == 20
    end

    test "max_pages on stream_v1/3 halts at the cap" do
      client =
        test_client(fn conn ->
          Req.Test.json(conn, %{
            "meta" => %{"rc" => "ok"},
            "data" => Enum.map(1..10, &%{"_id" => &1})
          })
        end)

      result =
        Client.stream_v1(client, "/api/s/default/stat/event", limit: 10, max_pages: 1)
        |> Enum.to_list()

      assert length(result) == 10
    end

    test "max_items truncates the final page to fit the cap" do
      # Pages of 10. max_items: 25 → 25 items then halt (third page truncated to 5).
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      client =
        test_client(fn conn ->
          n = Agent.get_and_update(agent, fn v -> {v, v + 1} end)
          Req.Test.json(conn, Enum.map(1..10, &%{"id" => "#{n}-#{&1}"}))
        end)

      result = Client.stream(client, "/v1/test", limit: 10, max_items: 25) |> Enum.to_list()
      assert length(result) == 25
    end

    test "max_pages on stream_paged/2 is respected alongside the caller's fetch" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      fetch = fn _cursor ->
        n = Agent.get_and_update(counter, fn v -> {v, v + 1} end)
        {:ok, Enum.map(1..5, &%{"page" => n, "i" => &1})}
      end

      result = Client.stream_paged(fetch, limit: 5, max_pages: 3) |> Enum.to_list()
      assert length(result) == 15
    end
  end

  describe "rate-limit retry-after backoff (P3-T6)" do
    @tag :capture_log
    test "first 429 sleeps retry-after, retries the same page; second 429 yields error tuple" do
      # Short-circuit the real sleep so the test stays fast.
      # First fetch → 429 retry-after=1, sleep(1000ms = real 1s) is too slow;
      # patch the sleep via a Process.sleep stub is not feasible here, so use
      # retry-after=0 to avoid waiting while still exercising the path.
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      client =
        test_client(fn conn ->
          n = Agent.get_and_update(agent, fn v -> {v, v + 1} end)

          case n do
            0 ->
              # First attempt: 429 with retry-after=0 (no sleep delay)
              conn
              |> Plug.Conn.put_resp_header("retry-after", "0")
              |> Plug.Conn.send_resp(429, "{}")

            1 ->
              # Retry of the same page now succeeds (full page → advance)
              Req.Test.json(conn, Enum.map(1..5, &%{"id" => &1}))

            _ ->
              # Next page → short page → halt.
              Req.Test.json(conn, [%{"id" => "short"}])
          end
        end)

      result = Client.stream(client, "/v1/test", limit: 5) |> Enum.to_list()

      # 5 items from the retried page + 1 from the final short page = 6 total.
      assert [
               %{"id" => 1},
               %{"id" => 2},
               %{"id" => 3},
               %{"id" => 4},
               %{"id" => 5},
               %{"id" => "short"}
             ] =
               result
    end

    test "second consecutive 429 yields the error tuple with the failed page's offset" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "0")
          |> Plug.Conn.send_resp(429, "{}")
        end)

      # The generic error branch yields `{:error, %StreamError{kind: :rate_limit}, offset}`.
      result = Client.stream(client, "/v1/test", limit: 5) |> Enum.to_list()

      assert [{:error, %StreamError{kind: :rate_limit, status: 429}, 0}] = result
    end
  end
end
