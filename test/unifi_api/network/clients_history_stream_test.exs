defmodule UnifiApi.Network.ClientsHistoryStreamTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.ClientsHistory

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "stream/3 paginates via pageSize / pageNumber until short page" do
    pages = [
      Enum.map(1..10, &%{"id" => "c#{&1}"}),
      Enum.map(11..20, &%{"id" => "c#{&1}"}),
      Enum.map(21..23, &%{"id" => "c#{&1}"})
    ]

    {:ok, agent} = Agent.start_link(fn -> {0, pages} end)

    client =
      test_client(fn conn ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        assert params["pageSize"] == "10"

        {expected_page, page} =
          Agent.get_and_update(agent, fn {n, [p | rest]} -> {{n, p}, {n + 1, rest}} end)

        assert params["pageNumber"] == to_string(expected_page)
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => page})
      end)

    assert clients = ClientsHistory.stream(client, "default", limit: 10) |> Enum.to_list()
    assert length(clients) == 23
  end
end
