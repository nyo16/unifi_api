defmodule UnifiApi.Network.StreamOptionsTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.{Alarms, ClientsHistory, Events, IDS, SystemLog}
  alias UnifiApi.StreamError

  # P4-T20. All five v1/v2 `stream/*` wrappers used to build their own
  # option list and drop `:max_pages` / `:max_items` / `:raise_errors`
  # before delegating, so `max_items: 100` — the same option name
  # `Client.stream/3` honours — silently paged the entire log. These
  # tests count requests through the plug, so a wrapper that stops
  # forwarding fails here instead of quietly walking the controller.

  # `stream/3` is `(client, site_id, opts)` on every one of the five, so
  # the option-validation contract can be asserted in one loop.
  @wrappers [Alarms, ClientsHistory, Events, IDS, SystemLog]

  # The fake log is this many full pages deep, then one short page. Full
  # pages mean only a *forwarded* cap can halt the stream; the finite
  # depth means a wrapper that drops the cap over-yields and fails an
  # assertion instead of paging forever.
  @log_depth 20

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  # Returns `{client, count_fn}`. `on_request` receives the decoded query
  # params and the zero-based request index.
  defp counting_client(page_size, on_request \\ fn _params, _n -> :ok end) do
    {:ok, requests} = Agent.start_link(fn -> 0 end)

    client =
      test_client(fn conn ->
        n = Agent.get_and_update(requests, fn v -> {v, v + 1} end)
        on_request.(Plug.Conn.fetch_query_params(conn).query_params, n)
        size = if n < @log_depth, do: page_size, else: 1

        Req.Test.json(conn, %{
          "meta" => %{"rc" => "ok"},
          "data" => Enum.map(1..size, &%{"id" => "#{n}-#{&1}", "_id" => "#{n}-#{&1}"})
        })
      end)

    {client, fn -> Agent.get(requests, & &1) end}
  end

  defp error_client(status) do
    test_client(fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, JSON.encode!(%{"error" => "boom"}))
    end)
  end

  describe "option validation" do
    test "every stream/3 rejects an unknown option key" do
      {client, _count} = counting_client(1)

      for mod <- @wrappers do
        assert_raise ArgumentError, fn -> mod.stream(client, "default", bogus: 1) end
      end
    end

    test "the ArgumentError names the offending key and the allowed set" do
      {client, _count} = counting_client(1)

      # A near-miss typo is the case that mattered: `max_item` used to be
      # accepted and ignored.
      err = assert_raise ArgumentError, fn -> Events.stream(client, "default", max_item: 5) end

      assert err.message =~ ":max_item"
      assert err.message =~ ":max_items"
    end

    test "validation happens eagerly, before the first request" do
      {client, count} = counting_client(10)

      assert_raise ArgumentError, fn -> SystemLog.stream(client, "default", nope: true) end
      assert count.() == 0
    end
  end

  describe "Alarms.stream/3 (stream_v1)" do
    test "forwards :max_items and keeps the caps out of the query string" do
      {client, count} =
        counting_client(10, fn params, _n ->
          assert params["archived"] == "false"
          assert params["_limit"] == "10"
          assert params["max_items"] == nil
        end)

      alarms =
        Alarms.stream(client, "default", archived: false, limit: 10, max_items: 25)
        |> Enum.to_list()

      assert length(alarms) == 25
      # Pages of 10, cap of 25 → three requests, the last truncated.
      assert count.() == 3
    end

    test "forwards :max_pages" do
      {client, count} = counting_client(10)

      alarms = Alarms.stream(client, "default", limit: 10, max_pages: 2) |> Enum.to_list()

      assert length(alarms) == 20
      assert count.() == 2
    end
  end

  describe "IDS.stream/3 (stream_v1)" do
    test "forwards :max_pages so max_pages: 1 issues exactly one request" do
      {client, count} = counting_client(10, fn params, _n -> assert params["within"] == "12" end)

      detections =
        IDS.stream(client, "default", within_hours: 12, limit: 10, max_pages: 1)
        |> Enum.to_list()

      assert length(detections) == 10
      assert count.() == 1
    end

    test "forwards :raise_errors" do
      client = error_client(500)

      assert_raise StreamError, fn ->
        IDS.stream(client, "default", raise_errors: true) |> Enum.to_list()
      end

      assert [{:error, %StreamError{kind: :api, status: 500}, 0}] =
               IDS.stream(client, "default") |> Enum.to_list()
    end
  end

  describe "ClientsHistory.stream/3 (stream_paged)" do
    test "forwards :max_items without double-applying :limit as pageSize" do
      {client, count} =
        counting_client(10, fn params, n ->
          # `:limit` is the wrapper's own key: it becomes `pageSize` once
          # and `stream_paged/2`'s short-page threshold once.
          assert params["pageSize"] == "10"
          assert params["pageNumber"] == to_string(n)
          assert params["searchString"] == "kitchen"
          assert params["max_items"] == nil
        end)

      clients =
        ClientsHistory.stream(client, "default", search: "kitchen", limit: 10, max_items: 25)
        |> Enum.to_list()

      assert length(clients) == 25
      assert count.() == 3
    end

    test "forwards :raise_errors" do
      client = error_client(502)

      assert_raise StreamError, fn ->
        ClientsHistory.stream(client, "default", raise_errors: true) |> Enum.to_list()
      end
    end
  end

  describe "SystemLog.stream/3 (stream_paged)" do
    test "forwards :max_pages so max_pages: 1 issues exactly one request" do
      {client, count} = counting_client(50)

      logs = SystemLog.stream(client, "default", limit: 50, max_pages: 1) |> Enum.to_list()

      assert length(logs) == 50
      assert count.() == 1
    end

    test "forwards :max_items and truncates the final page to fit" do
      {client, count} = counting_client(50)

      logs = SystemLog.stream(client, "default", limit: 50, max_items: 60) |> Enum.to_list()

      assert length(logs) == 60
      assert count.() == 2
    end
  end
end
