defmodule UnifiApi.Network.ActiveLeasesTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.ActiveLeases

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "list/2 hits /v2/api/site/{site}/active-leases" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/active-leases"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => [%{"mac" => "aa:bb"}]})
      end)

    assert {:ok, [%{"mac" => "aa:bb"}]} = ActiveLeases.list(client, "default")
  end

  test "list/3 forwards :params verbatim (the v2 paging escape hatch)" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/v2/api/site/default/active-leases"
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["pageSize"] == "500"
        assert params["pageNumber"] == "1"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, []} =
             ActiveLeases.list(client, "default", params: [pageSize: 500, pageNumber: 1])
  end

  test "list/3 with :raw skips JSON decoding and the envelope unwrap" do
    client =
      test_client(fn conn ->
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => []})
      end)

    assert {:ok, body} = ActiveLeases.list(client, "default", raw: true)
    assert is_binary(body)
  end

  # `:limit` / `:offset` are deliberately not accepted: this v2 handler does
  # not honour the v1 `_start` / `_limit` pair, so accepting them would
  # advertise a knob that silently does nothing.
  test "list/3 rejects :limit rather than sending a param the handler ignores" do
    client = test_client(fn conn -> Req.Test.json(conn, %{}) end)

    assert_raise ArgumentError, fn -> ActiveLeases.list(client, "default", limit: 100) end
  end
end
