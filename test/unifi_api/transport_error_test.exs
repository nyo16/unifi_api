defmodule UnifiApi.TransportErrorTest do
  use ExUnit.Case, async: true

  alias UnifiApi.{Client, StreamError, TransportError}

  # Transport-layer failure coverage for every `UnifiApi.Client` entry
  # point (v0.4.0 error umbrella, plan task 23).
  #
  # Why this file exists: before it, 297 tests stayed green against a
  # client that raised `ArgumentError` on every *real* request, because
  # the suite only ever drove the `Req.Test` plug adapter — which
  # short-circuits inside `Req.Finch` before transport options are ever
  # validated. `Req.Test.transport_error/2` stashes a
  # `%Req.TransportError{}` in `conn.private[:req_test_exception]`;
  # `Req.Plug` then hands it back as the adapter's `{:error, exception}`
  # instead of a response (deps/req/lib/req/plug.ex:213). That is the
  # closest a plug can get to a real connection failure, so it is what
  # the matrix below uses.
  #
  # The complementary *real adapter* coverage — `Client.new/1`'s own
  # `:finch` / `:transport_opts` struct driven through Finch against a
  # live `:ssl` server — lives in the `fingerprint pinning — real TLS
  # handshake` describe block of `test/unifi_api/client_test.exs`. It is
  # deliberately not duplicated here.
  #
  # `Client.retry_transient/2` is unit-tested as a pure function in
  # `test/unifi_api/client_test.exs` ("retry_transient/2"). The retry
  # section at the bottom of this file covers the part that cannot:
  # whether `Client.new/1` actually wires it up and whether a request is
  # genuinely re-issued end to end.

  defp test_client(plug) do
    Req.new(
      base_url: "http://localhost",
      headers: [{"x-api-key", "test-key"}],
      plug: plug,
      retry: false
    )
  end

  defp refusing_client do
    test_client(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
  end

  # Every wrapping entry point funnels through `UnifiApi.Error.from_transport/1`,
  # so the assertion is identical: the umbrella struct carries the atom
  # reason and keeps Req's own exception in `:original`.
  defp assert_wrapped(result, reason) do
    assert {:error, %TransportError{reason: ^reason, original: original}} = result
    assert %Req.TransportError{reason: ^reason} = original
  end

  describe "transport errors — request entry points" do
    test "get/3 wraps in %UnifiApi.TransportError{}" do
      assert_wrapped(Client.get(refusing_client(), "/v1/sites"), :econnrefused)
    end

    test "get/3 with raw: true (decode_body: false) wraps too" do
      assert_wrapped(Client.get(refusing_client(), "/v1/sites", raw: true), :econnrefused)
    end

    test "get_v1/3 wraps before the envelope unwrap can run" do
      assert_wrapped(Client.get_v1(refusing_client(), "/api/s/default/stat/event"), :econnrefused)
    end

    test "get_v1/3 with raw: true (its own case branch) wraps too" do
      assert_wrapped(
        Client.get_v1(refusing_client(), "/api/s/default/stat/event", raw: true),
        :econnrefused
      )
    end

    test "post/4 wraps in %UnifiApi.TransportError{}" do
      assert_wrapped(Client.post(refusing_client(), "/v1/sites/s-1/networks", %{}), :econnrefused)
    end

    test "put/4 wraps in %UnifiApi.TransportError{}" do
      assert_wrapped(
        Client.put(refusing_client(), "/v1/sites/s-1/networks/n-1", %{}),
        :econnrefused
      )
    end

    test "patch/4 wraps in %UnifiApi.TransportError{}" do
      assert_wrapped(Client.patch(refusing_client(), "/v1/cameras/cam-1", %{}), :econnrefused)
    end

    test "delete/3 wraps in %UnifiApi.TransportError{}" do
      assert_wrapped(
        Client.delete(refusing_client(), "/v1/sites/s-1/networks/n-1"),
        :econnrefused
      )
    end

    test "get_raw/3 wraps in %UnifiApi.TransportError{}" do
      assert_wrapped(
        Client.get_raw(refusing_client(), "/v1/cameras/cam-1/snapshot"),
        :econnrefused
      )
    end

    # `raw_get/3` is the one deliberate hole in the umbrella: it is the
    # "give me the untouched `Req` result" escape hatch, returns
    # `Req.get/2` verbatim, and its `@spec` says `{:error, term()}`
    # rather than `{:error, UnifiApi.Error.t()}`. Pinned here so the
    # asymmetry is a decision on record, not a surprise: callers of
    # `raw_get/3` must run the result through
    # `UnifiApi.Error.from_transport/1` themselves. Both in-tree callers,
    # `UnifiApi.detect/1` and `UnifiApi.ping/1`, do — proven in
    # `test/unifi_api_test.exs` alongside their status coverage.
    test "raw_get/3 surfaces Req's own %Req.TransportError{} UNWRAPPED" do
      assert {:error, %Req.TransportError{reason: :econnrefused}} =
               Client.raw_get(refusing_client(), "/")
    end

    test "UnifiApi.Error.from_transport/1 is what a raw_get/3 caller must apply" do
      {:error, raw} = Client.raw_get(refusing_client(), "/")

      assert %TransportError{reason: :econnrefused, original: ^raw} =
               UnifiApi.Error.from_transport(raw)
    end
  end

  describe "transport errors — stream entry points" do
    # `build_stream_error/2` classifies `%UnifiApi.TransportError{}` as
    # `{:transport, :unknown}`: there is no HTTP status to report because
    # no response ever arrived.
    defp assert_transport_stream_tail(list, cursor) do
      assert [
               {:error,
                %StreamError{
                  kind: :transport,
                  status: :unknown,
                  reason: %TransportError{reason: :econnrefused}
                }, ^cursor}
             ] = list
    end

    test "stream/3 yields the {:error, %StreamError{kind: :transport}, cursor} tail" do
      Client.stream(refusing_client(), "/v1/sites/s-1/devices", limit: 5)
      |> Enum.to_list()
      |> assert_transport_stream_tail(0)
    end

    test "stream/3 with raise_errors: true raises %StreamError{kind: :transport}" do
      error =
        assert_raise StreamError, fn ->
          Client.stream(refusing_client(), "/v1/sites/s-1/devices",
            limit: 5,
            raise_errors: true
          )
          |> Enum.to_list()
        end

      assert %StreamError{
               kind: :transport,
               status: :unknown,
               reason: %TransportError{reason: :econnrefused, original: %Req.TransportError{}}
             } = error
    end

    test "stream_v1/3 yields the {:error, %StreamError{kind: :transport}, cursor} tail" do
      Client.stream_v1(refusing_client(), "/api/s/default/stat/event", limit: 5)
      |> Enum.to_list()
      |> assert_transport_stream_tail(0)
    end

    test "stream_v1/3 with raise_errors: true raises %StreamError{kind: :transport}" do
      error =
        assert_raise StreamError, fn ->
          Client.stream_v1(refusing_client(), "/api/s/default/stat/event",
            limit: 5,
            raise_errors: true
          )
          |> Enum.to_list()
        end

      assert %StreamError{kind: :transport, reason: %TransportError{reason: :econnrefused}} =
               error
    end

    test "stream_paged/2 yields the {:error, %StreamError{kind: :transport}, cursor} tail" do
      client = refusing_client()

      fetch = fn page ->
        Client.get(client, "/v2/api/site/default/system-log/all", params: [pageNumber: page])
      end

      Client.stream_paged(fetch, limit: 5, start_at: 1)
      |> Enum.to_list()
      |> assert_transport_stream_tail(1)
    end

    test "stream_paged/2 with raise_errors: true raises %StreamError{kind: :transport}" do
      client = refusing_client()

      fetch = fn page ->
        Client.get(client, "/v2/api/site/default/system-log/all", params: [pageNumber: page])
      end

      error =
        assert_raise StreamError, fn ->
          Client.stream_paged(fetch, limit: 5, raise_errors: true) |> Enum.to_list()
        end

      assert %StreamError{kind: :transport, reason: %TransportError{reason: :econnrefused}} =
               error
    end

    test "a mid-stream transport error reports the failed page's cursor, not 0" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      client =
        test_client(fn conn ->
          case Agent.get_and_update(agent, fn v -> {v, v + 1} end) do
            # Full page → the stream advances the cursor to 5 and fetches again.
            0 -> Req.Test.json(conn, Enum.map(1..5, &%{"id" => &1}))
            _ -> Req.Test.transport_error(conn, :closed)
          end
        end)

      result = Client.stream(client, "/v1/sites/s-1/devices", limit: 5) |> Enum.to_list()
      {items, tail} = Enum.split(result, 5)

      assert length(items) == 5

      assert [
               {:error,
                %StreamError{
                  kind: :transport,
                  status: :unknown,
                  reason: %TransportError{reason: :closed}
                }, 5}
             ] = tail
    end
  end

  describe "timeouts" do
    test "get/3 propagates %UnifiApi.TransportError{reason: :timeout}" do
      client = test_client(fn conn -> Req.Test.transport_error(conn, :timeout) end)
      assert_wrapped(Client.get(client, "/v1/sites"), :timeout)
    end

    test "post/4 propagates %UnifiApi.TransportError{reason: :timeout}" do
      client = test_client(fn conn -> Req.Test.transport_error(conn, :timeout) end)
      assert_wrapped(Client.post(client, "/v1/sites/s-1/networks", %{}), :timeout)
    end

    test "a timeout mid-stream becomes %StreamError{kind: :transport}" do
      client = test_client(fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert [
               {:error,
                %StreamError{
                  kind: :transport,
                  status: :unknown,
                  reason: %TransportError{reason: :timeout}
                }, 0}
             ] = Client.stream(client, "/v1/sites/s-1/devices", limit: 5) |> Enum.to_list()
    end

    test "message/1 names the reason without inventing a status" do
      client = test_client(fn conn -> Req.Test.transport_error(conn, :timeout) end)
      {:error, error} = Client.get(client, "/v1/sites")

      assert Exception.message(error) ==
               "transport failure before any HTTP response: :timeout"
    end
  end

  describe "malformed JSON body" do
    # FINDING (measured, not assumed). With no `content-type` header,
    # Req's `decode_body` step falls back to `application/octet-stream`,
    # finds no matching decoder, and passes the body through untouched —
    # so a 200 with a truncated JSON body is reported as SUCCESS carrying
    # the raw binary. Lossy: a caller that expects `{:ok, map}` gets
    # `{:ok, binary}` and only discovers it downstream. Not something
    # this library can fix without second-guessing the controller's
    # content type, but pinned so the behaviour is on record.
    test "get/3 returns {:ok, raw_binary} when the body has no content-type" do
      client = test_client(fn conn -> Plug.Conn.send_resp(conn, 200, "{not json") end)

      assert Client.get(client, "/v1/sites") == {:ok, "{not json"}
    end

    # FINDING (measured). With `content-type: application/json` the
    # decoder *does* run, `Jason.decode/1` fails, and Req replaces the
    # response with the `%Jason.DecodeError{}` exception — which reaches
    # the library as `{:error, exception}`, indistinguishable from an
    # adapter failure. `UnifiApi.Error.from_transport/1` therefore
    # classifies it as a `TransportError`, even though an HTTP 200
    # response definitely *did* arrive. Two consequences worth knowing:
    #
    #   1. `:reason` holds a struct, not an atom, so
    #      `%TransportError{reason: :timeout}`-style matching silently
    #      misses it; the moduledoc's "never produced an HTTP response"
    #      contract is violated. An `%ApiError{status: 200}` would be the
    #      honest classification.
    #   2. `%Jason.DecodeError{data:}` carries the RAW response body,
    #      and `TransportError.message/1` renders `inspect(reason)` — so
    #      the unscrubbed body reaches logs, bypassing
    #      `Client.scrub_body_preview/1` (CWE-209).
    #
    # Asserted exactly as observed. `Jason` is Req's own decoder (a
    # transitive dep), which is why its struct appears in our contract.
    test "get/3 wraps a JSON decode failure as %TransportError{reason: %Jason.DecodeError{}}" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, "{not json")
        end)

      assert {:error, %TransportError{reason: reason, original: original}} =
               Client.get(client, "/v1/sites")

      assert %Jason.DecodeError{position: 1, token: nil, data: "{not json"} = reason
      assert original == reason
    end
  end

  # `Client.new/1` replaced Req's `retry: :safe_transient` preset with
  # `retry: &Client.retry_transient/2`. `client_test.exs` proves the
  # predicate's truth table; these prove the wiring — that a real
  # request is actually re-issued (or not) through the full Req pipeline.
  describe "retry: &Client.retry_transient/2 end to end" do
    test "new/1 installs a predicate function, not Req's :safe_transient preset" do
      client = Client.new(base_url: "http://localhost")
      retry = client.options[:retry]

      # Req's own preset is the atom `:safe_transient`; ours is a
      # function. Identity comparison is impossible — inside the module
      # `&retry_transient/2` compiles to a local capture, not
      # `&UnifiApi.Client.retry_transient/2` — so check what it decides.
      assert is_function(retry, 2)

      assert retry.(%Req.Request{method: :get}, %Req.TransportError{reason: :econnrefused}) ==
               true

      assert retry.(%Req.Request{method: :get}, %Req.TransportError{reason: :nxdomain}) == false

      assert retry.(%Req.Request{method: :post}, %Req.TransportError{reason: :econnrefused}) ==
               false

      assert client.options[:max_retries] == 1

      # `max_retries: 0` has to disable retry outright: leaving the
      # predicate installed with a zero budget still costs a pipeline step.
      disabled = Client.new(base_url: "http://localhost", max_retries: 0)
      assert disabled.options[:retry] == false
    end

    # `retry_transient/2` returns a bare `true` for transport errors and
    # for statuses with no `Retry-After`, which lets Req consult
    # `:retry_delay`. Pinning it to 0 keeps the suite fast; Req only
    # forbids `:retry_delay` alongside a `{:delay, ms}` return, which is
    # the 429/503-with-Retry-After case and is not exercised here.
    defp counting_client(plug_fun) do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      client =
        Client.new(base_url: "http://localhost", api_key: "test-key")
        |> Req.merge(
          plug: fn conn -> plug_fun.(conn, Agent.get_and_update(agent, &{&1, &1 + 1})) end,
          max_retries: 1,
          retry_delay: 0,
          retry_log_level: false
        )

      {client, fn -> Agent.get(agent, & &1) end}
    end

    test "a transient transport error on GET is retried and then succeeds" do
      {client, calls} =
        counting_client(fn
          conn, 0 -> Req.Test.transport_error(conn, :econnrefused)
          conn, _ -> Req.Test.json(conn, %{"ok" => true})
        end)

      assert {:ok, %{"ok" => true}} = Client.get(client, "/v1/sites")
      assert calls.() == 2
    end

    test "a transient 503 on GET is retried and then succeeds" do
      {client, calls} =
        counting_client(fn
          conn, 0 -> Plug.Conn.send_resp(conn, 503, "")
          conn, _ -> Req.Test.json(conn, %{"ok" => true})
        end)

      assert {:ok, %{"ok" => true}} = Client.get(client, "/v1/sites")
      assert calls.() == 2
    end

    # "safe": a retry would re-apply a mutation, so non-idempotent
    # methods surface the failure on the first attempt.
    test "a transport error on POST is NOT retried" do
      {client, calls} =
        counting_client(fn conn, _ -> Req.Test.transport_error(conn, :econnrefused) end)

      assert_wrapped(Client.post(client, "/v1/sites/s-1/networks", %{}), :econnrefused)
      assert calls.() == 1
    end

    # "transient": only :timeout / :econnrefused / :closed are worth a
    # second attempt. A DNS failure will not fix itself in 0ms.
    test "a non-transient transport reason on GET is NOT retried" do
      {client, calls} =
        counting_client(fn conn, _ -> Req.Test.transport_error(conn, :nxdomain) end)

      assert_wrapped(Client.get(client, "/v1/sites"), :nxdomain)
      assert calls.() == 1
    end

    # Streams override the client with `retry: false` per page: re-issuing
    # a paginated read after a backoff risks duplicate/stale rows.
    test "stream/3 does not retry a transient transport error" do
      {client, calls} =
        counting_client(fn conn, _ -> Req.Test.transport_error(conn, :econnrefused) end)

      result = Client.stream(client, "/v1/sites/s-1/devices", limit: 5) |> Enum.to_list()

      assert [{:error, %StreamError{kind: :transport}, 0}] = result
      assert calls.() == 1
    end
  end
end
