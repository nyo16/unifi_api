defmodule UnifiApi.Network.SystemLogStreamTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.SystemLog

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "stream/3 paginates the system log via pageSize / pageNumber" do
    pages = [
      Enum.map(1..50, &%{"id" => "log#{&1}"}),
      Enum.map(51..52, &%{"id" => "log#{&1}"})
    ]

    {:ok, agent} = Agent.start_link(fn -> pages end)

    client =
      test_client(fn conn ->
        page = Agent.get_and_update(agent, fn [h | t] -> {h, t} end)
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => page})
      end)

    assert logs = SystemLog.stream(client, "default", limit: 50) |> Enum.to_list()
    assert length(logs) == 52
  end
end
