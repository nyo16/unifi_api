defmodule UnifiApi.ErrorTest do
  use ExUnit.Case, async: true

  alias UnifiApi.{AuthError, Client, RateLimitError}

  defp test_client(plug) do
    Req.new(
      base_url: "http://localhost",
      headers: [{"x-api-key", "test-key"}],
      plug: plug,
      retry: false
    )
  end

  describe "RateLimitError" do
    test "is returned for 429 with Retry-After in seconds" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "42")
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(429, JSON.encode!(%{"error" => "slow down"}))
        end)

      assert {:error,
              %RateLimitError{
                retry_after: 42,
                status: 429,
                body: %{"error" => "slow down"}
              }} = Client.get(client, "/v1/test")
    end

    test "defaults to 60 seconds when Retry-After is missing" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(429, JSON.encode!(%{}))
        end)

      assert {:error, %RateLimitError{retry_after: 60}} = Client.get(client, "/v1/test")
    end

    test "clamps retry_after below 1 second up to 1" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "0")
          |> Plug.Conn.send_resp(429, "{}")
        end)

      assert {:error, %RateLimitError{retry_after: 1}} = Client.get(client, "/v1/test")
    end

    test "clamps retry_after above 300 seconds down to 300" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "9999")
          |> Plug.Conn.send_resp(429, "{}")
        end)

      assert {:error, %RateLimitError{retry_after: 300}} = Client.get(client, "/v1/test")
    end

    test "falls back to 60 when Retry-After is unparseable" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "garbage")
          |> Plug.Conn.send_resp(429, "{}")
        end)

      assert {:error, %RateLimitError{retry_after: 60}} = Client.get(client, "/v1/test")
    end

    test "Exception.message/1 mentions the retry interval" do
      err = %RateLimitError{retry_after: 90, status: 429, body: nil}
      assert Exception.message(err) =~ "90s"
    end
  end

  describe "AuthError" do
    test "is returned for 401 with reason :unauthorized" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(401, JSON.encode!(%{"error" => "bad key"}))
        end)

      assert {:error,
              %AuthError{status: 401, reason: :unauthorized, body: %{"error" => "bad key"}}} =
               Client.get(client, "/v1/test")
    end

    test "is returned for 403 with reason :forbidden" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(403, JSON.encode!(%{"error" => "no access"}))
        end)

      assert {:error, %AuthError{status: 403, reason: :forbidden}} =
               Client.get(client, "/v1/test")
    end

    test "Exception.message/1 distinguishes the two reasons" do
      assert Exception.message(%AuthError{status: 401, reason: :unauthorized}) =~ "401"
      assert Exception.message(%AuthError{status: 403, reason: :forbidden}) =~ "403"
    end
  end

  describe "other non-2xx responses" do
    test "still return {:error, {status, body}}" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(404, JSON.encode!(%{"error" => "missing"}))
        end)

      assert {:error, {404, %{"error" => "missing"}}} = Client.get(client, "/v1/test")
    end
  end
end
