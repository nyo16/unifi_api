defmodule UnifiApi.ErrorTest do
  use ExUnit.Case, async: true

  alias UnifiApi.{ApiError, AuthError, Client, RateLimitError}

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
                body_preview: preview
              }} = Client.get(client, "/v1/test")

      assert is_binary(preview)
      assert preview =~ "slow down"
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
      err = %RateLimitError{retry_after: 90, status: 429, body_preview: nil}
      assert Exception.message(err) =~ "90s"
    end

    test "body_preview redacts URLs and hosts and truncates" do
      long_url = "https://controller.example.com/internal/path?token=secret&x=1"
      preview = Client.scrub_body_preview(long_url)
      assert is_binary(preview)
      refute preview =~ "controller.example.com"
      refute preview =~ "secret"
      assert byte_size(preview) <= 128
    end

    test "body_preview redacts IPv4 literals" do
      preview = Client.scrub_body_preview("connect to 192.168.1.1 please")
      refute preview =~ "192.168.1.1"
    end

    test "body_preview returns nil for empty bodies" do
      assert Client.scrub_body_preview(nil) == nil
      assert Client.scrub_body_preview("") == nil
    end

    test "body_preview truncates before scrubbing, not after" do
      # Each redaction is a full-body regex pass. Scrubbing first cost
      # ~32ms and ~2.6 MB of garbage on an 897 KB body to produce 128
      # characters, on every 401/403/429. Truncating first makes the work
      # proportional to the *output*, not the body.
      body =
        String.duplicate(~s({"error":"denied at https://10.0.0.1/x for udm.example.com"}), 13_000)

      assert byte_size(body) > 700_000

      {micros, preview} = :timer.tc(fn -> Client.scrub_body_preview(body) end)

      # Redaction still happens — the window is scanned, just a small one.
      refute preview =~ "10.0.0.1"
      refute preview =~ "udm.example.com"
      assert preview =~ "[url]"
      assert preview =~ "[host]"
      assert String.length(preview) <= 128

      # Generous ceiling: measured ~24us here versus ~32_000us for the old
      # order, so this only trips on a return to whole-body scanning.
      assert micros < 5_000
    end

    test "body_preview never returns invalid UTF-8 from a mid-codepoint cut" do
      # The scan window is a `binary_part/3`, which can split a multi-byte
      # codepoint; the regex passes need valid UTF-8.
      body = String.duplicate("é", 1_000)

      preview = Client.scrub_body_preview(body)

      assert String.valid?(preview)
      assert String.length(preview) <= 128
    end

    test "body_preview handles a non-UTF-8 binary body" do
      preview = Client.scrub_body_preview(:crypto.strong_rand_bytes(4_000))

      assert is_binary(preview)
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

      assert {:error, %AuthError{status: 401, reason: :unauthorized, body_preview: preview}} =
               Client.get(client, "/v1/test")

      assert is_binary(preview)
      assert preview =~ "bad key"
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
    test "return %ApiError{} carrying the status and a scrubbed body preview" do
      client =
        test_client(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(404, JSON.encode!(%{"error" => "missing"}))
        end)

      assert {:error, %ApiError{status: 404, code: nil, body_preview: preview}} =
               Client.get(client, "/v1/test")

      # Body is scrubbed/truncated into a preview string, never the raw map.
      assert is_binary(preview)
      assert preview =~ "missing"
    end
  end
end
