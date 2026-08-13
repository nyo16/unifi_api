defmodule UnifiApi.Network.EventsTest do
  use ExUnit.Case, async: true

  alias UnifiApi.ApiError
  alias UnifiApi.Network.Events
  alias UnifiApi.StreamError

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/3 hits /proxy/network/api/s/{site}/stat/event and unwraps data" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/event"

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => [
            %{"_id" => "e1", "key" => "EVT_AP_Connected", "subsystem" => "wlan"},
            %{"_id" => "e2", "key" => "EVT_LU_Disconnected", "subsystem" => "lan"}
          ]
        })
      end)

    assert {:ok, [%{"_id" => "e1"}, %{"_id" => "e2"}]} = Events.list(client, "default")
  end

  test "list/3 forwards within_hours, limit, start as v1 query params" do
    client =
      test_client(fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["within"] == "24"
        assert params["_limit"] == "100"
        assert params["_start"] == "0"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} = Events.list(client, "default", within_hours: 24, limit: 100, start: 0)
  end

  test "list/3 surfaces meta.rc == error as %ApiError{}" do
    client =
      test_client(fn conn ->
        Req.Test.json(conn, %{"meta" => %{"rc" => "error", "msg" => "api.err.LoginRequired"}})
      end)

    # v1 envelope failures arrive with HTTP 200; the failure lives in the body.
    assert {:error, %ApiError{status: 200, code: "api.err.LoginRequired"}} =
             Events.list(client, "default")
  end

  test "list/3 with raw: true skips JSON decoding and v1 unwrap" do
    payload = ~s|{"meta":{"rc":"ok"},"data":[{"_id":"e1","key":"raw"}]}|

    client =
      test_client(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, payload)
      end)

    # With raw: true, the response body is returned verbatim (still
    # tagged :ok because transport succeeded).
    assert {:ok, ^payload} = Events.list(client, "default", raw: true)
  end

  describe "stream/3" do
    test "auto-paginates via _start / _limit until a short page" do
      pages = [
        Enum.map(1..10, &%{"_id" => "e#{&1}"}),
        Enum.map(11..20, &%{"_id" => "e#{&1}"}),
        Enum.map(21..23, &%{"_id" => "e#{&1}"})
      ]

      {:ok, agent} = Agent.start_link(fn -> pages end)

      client =
        test_client(fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["_limit"] == "10"
          assert params["within"] == "1"

          page = Agent.get_and_update(agent, fn [h | t] -> {h, t} end)
          Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => page})
        end)

      assert events =
               Events.stream(client, "default", within_hours: 1, limit: 10)
               |> Enum.to_list()

      assert length(events) == 23
    end

    test "default page_size has dropped to 200 (P3-T5)" do
      client =
        test_client(fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["_limit"] == "200"
          Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
        end)

      assert [] = Events.stream(client, "default", within_hours: 1) |> Enum.to_list()
    end

    test "halts early when consumer takes a fixed amount" do
      client =
        test_client(fn conn ->
          Req.Test.json(conn, %{
            "meta" => %{"rc" => "ok"},
            "data" => Enum.map(1..500, &%{"_id" => "e#{&1}"})
          })
        end)

      # Limit takes only 5 — single page fetched, stream halts
      assert events = Events.stream(client, "default", limit: 500) |> Enum.take(5)
      assert length(events) == 5
    end

    # P4-T20: these three keys used to be dropped on the floor, so
    # `max_items: 100` paged the entire event log with no error.
    test "forwards :max_items and truncates the final page to fit (P4-T20)" do
      {:ok, requests} = Agent.start_link(fn -> 0 end)

      client =
        test_client(fn conn ->
          n = Agent.get_and_update(requests, fn v -> {v, v + 1} end)
          params = Plug.Conn.fetch_query_params(conn).query_params

          # Stream caps travel as `Client.stream_v1/3` options, never as
          # query params.
          assert params["max_items"] == nil

          # A finite fake log — 20 full pages then a short one — so a
          # wrapper that drops the cap over-yields and fails the count
          # below instead of paging forever.
          size = if n < 20, do: 10, else: 1

          Req.Test.json(conn, %{
            "meta" => %{"rc" => "ok"},
            "data" => Enum.map(1..size, &%{"_id" => "e#{n}-#{&1}"})
          })
        end)

      events = Events.stream(client, "default", limit: 10, max_items: 25) |> Enum.to_list()

      assert length(events) == 25
      # Pages of 10, cap of 25 → three requests, the last one truncated.
      assert Agent.get(requests, & &1) == 3
    end

    test "forwards :max_pages so max_pages: 1 issues exactly one request (P4-T20)" do
      {:ok, requests} = Agent.start_link(fn -> 0 end)

      client =
        test_client(fn conn ->
          n = Agent.get_and_update(requests, fn v -> {v, v + 1} end)
          size = if n < 20, do: 10, else: 1

          Req.Test.json(conn, %{
            "meta" => %{"rc" => "ok"},
            "data" => Enum.map(1..size, &%{"_id" => "e#{n}-#{&1}"})
          })
        end)

      events = Events.stream(client, "default", limit: 10, max_pages: 1) |> Enum.to_list()

      assert length(events) == 10
      assert Agent.get(requests, & &1) == 1
    end

    test "forwards :raise_errors so a mid-stream error raises (P4-T20)" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "boom"}))
        end)

      assert_raise StreamError, fn ->
        Events.stream(client, "default", raise_errors: true) |> Enum.to_list()
      end

      # Default is still the error-tuple tail, not a raise.
      assert [{:error, %StreamError{kind: :api, status: 500}, 0}] =
               Events.stream(client, "default") |> Enum.to_list()
    end
  end
end
