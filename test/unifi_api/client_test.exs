defmodule UnifiApi.ClientTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Client

  defp test_client(plug) do
    Req.new(
      base_url: "http://localhost",
      headers: [{"x-api-key", "test-key"}],
      plug: plug,
      retry: false
    )
  end

  describe "new/1" do
    test "returns a Req.Request struct" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "abc")
      assert %Req.Request{} = client
    end

    test "sends x-api-key header" do
      client =
        Client.new(base_url: "http://localhost", api_key: "secret123")
        |> Req.merge(
          plug: fn conn ->
            [key] = Plug.Conn.get_req_header(conn, "x-api-key")
            Req.Test.json(conn, %{"key" => key})
          end
        )

      assert {:ok, %{"key" => "secret123"}} = Client.get(client, "/v1/info")
    end

    test "sets base_url without path prefix" do
      client =
        Client.new(base_url: "http://localhost", api_key: "k")
        |> Req.merge(
          plug: fn conn ->
            Req.Test.json(conn, %{"path" => conn.request_path})
          end
        )

      assert {:ok, %{"path" => "/v1/info"}} = Client.get(client, "/v1/info")
    end

    test "respects verify_ssl: true" do
      client = Client.new(base_url: "https://10.0.0.1", api_key: "abc", verify_ssl: true)
      assert %Req.Request{} = client
      # When verify_ssl is true, connect_options should be empty (no verify_none)
      assert client.options.connect_options == []
    end
  end

  describe "get/3" do
    test "returns {:ok, body} on 200" do
      client =
        test_client(fn conn ->
          assert conn.method == "GET"
          Req.Test.json(conn, %{"data" => "hello"})
        end)

      assert {:ok, %{"data" => "hello"}} = Client.get(client, "/v1/test")
    end

    test "returns {:error, {status, body}} on 404" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(404, JSON.encode!(%{"error" => "not found"}))
        end)

      assert {:error, {404, %{"error" => "not found"}}} = Client.get(client, "/v1/missing")
    end

    test "returns {:error, {status, body}} on 500" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "internal"}))
        end)

      assert {:error, {500, _body}} = Client.get(client, "/v1/broken")
    end

    test "passes offset, limit, and filter as query params" do
      client =
        test_client(fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          Req.Test.json(conn, params)
        end)

      assert {:ok, %{"offset" => "10", "limit" => "50", "filter" => "name.eq(foo)"}} =
               Client.get(client, "/v1/test", offset: 10, limit: 50, filter: "name.eq(foo)")
    end

    test "returns {:error, {401, body}} on unauthorized" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(401, JSON.encode!(%{"error" => "unauthorized"}))
        end)

      assert {:error, {401, %{"error" => "unauthorized"}}} = Client.get(client, "/v1/test")
    end
  end

  describe "post/4" do
    test "sends JSON body and returns {:ok, body}" do
      client =
        test_client(fn conn ->
          assert conn.method == "POST"
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          body = JSON.decode!(raw)
          Req.Test.json(conn, %{"received" => body})
        end)

      assert {:ok, %{"received" => %{"name" => "test"}}} =
               Client.post(client, "/v1/resource", %{name: "test"})
    end

    test "returns {:error, {status, body}} on error" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(422, JSON.encode!(%{"error" => "validation failed"}))
        end)

      assert {:error, {422, %{"error" => "validation failed"}}} =
               Client.post(client, "/v1/resource", %{name: ""})
    end
  end

  describe "put/4" do
    test "sends JSON body and returns {:ok, body}" do
      client =
        test_client(fn conn ->
          assert conn.method == "PUT"
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          body = JSON.decode!(raw)
          Req.Test.json(conn, %{"received" => body})
        end)

      assert {:ok, %{"received" => %{"name" => "updated"}}} =
               Client.put(client, "/v1/resource/1", %{name: "updated"})
    end
  end

  describe "patch/4" do
    test "sends JSON body and returns {:ok, body}" do
      client =
        test_client(fn conn ->
          assert conn.method == "PATCH"
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          body = JSON.decode!(raw)
          Req.Test.json(conn, %{"received" => body})
        end)

      assert {:ok, %{"received" => %{"field" => "value"}}} =
               Client.patch(client, "/v1/resource/1", %{field: "value"})
    end
  end

  describe "delete/3" do
    test "returns {:ok, body} on success" do
      client =
        test_client(fn conn ->
          assert conn.method == "DELETE"
          Req.Test.json(conn, %{"deleted" => true})
        end)

      assert {:ok, %{"deleted" => true}} = Client.delete(client, "/v1/resource/1")
    end
  end

  describe "get_raw/3" do
    test "returns raw binary body" do
      client =
        test_client(fn conn ->
          assert conn.method == "GET"

          conn
          |> Plug.Conn.put_resp_content_type("image/jpeg")
          |> Plug.Conn.send_resp(200, <<0xFF, 0xD8, 0xFF>>)
        end)

      assert {:ok, <<0xFF, 0xD8, 0xFF>>} = Client.get_raw(client, "/v1/snapshot")
    end

    test "returns {:error, {status, body}} on failure" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(403, JSON.encode!(%{"error" => "forbidden"}))
        end)

      assert {:error, {403, _}} = Client.get_raw(client, "/v1/snapshot")
    end

    test "passes highQuality param" do
      client =
        test_client(fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          Req.Test.json(conn, params)
        end)

      assert {:ok, %{"highQuality" => "true"}} =
               Client.get_raw(client, "/v1/snapshot", high_quality: true)
    end
  end

  describe "stream/3" do
    test "streams through multiple pages" do
      page_count = :counters.new(1, [:atomics])

      client =
        test_client(fn conn ->
          :counters.add(page_count, 1, 1)
          params = Plug.Conn.fetch_query_params(conn).query_params
          offset = String.to_integer(params["offset"] || "0")

          items =
            case offset do
              0 -> Enum.map(1..3, &%{"id" => &1})
              3 -> Enum.map(4..6, &%{"id" => &1})
              6 -> [%{"id" => 7}]
            end

          Req.Test.json(conn, items)
        end)

      result = Client.stream(client, "/v1/test", limit: 3) |> Enum.to_list()

      assert length(result) == 7
      assert List.first(result)["id"] == 1
      assert List.last(result)["id"] == 7
      assert :counters.get(page_count, 1) == 3
    end

    test "halts when first page is smaller than limit" do
      client =
        test_client(fn conn ->
          Req.Test.json(conn, [%{"id" => 1}, %{"id" => 2}])
        end)

      result = Client.stream(client, "/v1/test", limit: 5) |> Enum.to_list()
      assert length(result) == 2
    end

    test "handles empty first page" do
      client =
        test_client(fn conn ->
          Req.Test.json(conn, [])
        end)

      result = Client.stream(client, "/v1/test") |> Enum.to_list()
      assert result == []
    end

    test "is lazy — stops fetching after Enum.take" do
      page_count = :counters.new(1, [:atomics])

      client =
        test_client(fn conn ->
          :counters.add(page_count, 1, 1)
          items = Enum.map(1..3, &%{"id" => &1})
          Req.Test.json(conn, items)
        end)

      result = Client.stream(client, "/v1/test", limit: 3) |> Enum.take(2)

      assert length(result) == 2
      assert :counters.get(page_count, 1) == 1
    end

    test "passes filter to every page request" do
      client =
        test_client(fn conn ->
          params = Plug.Conn.fetch_query_params(conn).query_params
          assert params["filter"] == "type.eq(WIRELESS)"

          items =
            if params["offset"] == "0",
              do: [%{"id" => 1}, %{"id" => 2}],
              else: [%{"id" => 3}]

          Req.Test.json(conn, items)
        end)

      result =
        Client.stream(client, "/v1/test", limit: 2, filter: "type.eq(WIRELESS)")
        |> Enum.to_list()

      assert length(result) == 3
    end

    test "raises StreamError on API error" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "boom"}))
        end)

      assert_raise UnifiApi.StreamError, ~r/stream request to/, fn ->
        Client.stream(client, "/v1/test") |> Enum.to_list()
      end
    end

    test "raises StreamError on error mid-stream (after successful first page)" do
      page_count = :counters.new(1, [:atomics])

      client =
        test_client(fn conn ->
          :counters.add(page_count, 1, 1)
          count = :counters.get(page_count, 1)

          if count == 1 do
            Req.Test.json(conn, Enum.map(1..3, &%{"id" => &1}))
          else
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(500, JSON.encode!(%{"error" => "boom"}))
          end
        end)

      assert_raise UnifiApi.StreamError, ~r/stream request to/, fn ->
        Client.stream(client, "/v1/test", limit: 3) |> Enum.to_list()
      end
    end

    test "raises StreamError on non-list response" do
      client =
        test_client(fn conn ->
          Req.Test.json(conn, %{"message" => "not a list"})
        end)

      assert_raise UnifiApi.StreamError, ~r/stream request to/, fn ->
        Client.stream(client, "/v1/test") |> Enum.to_list()
      end
    end
  end
end
