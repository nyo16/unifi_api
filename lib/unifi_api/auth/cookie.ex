defmodule UnifiApi.Auth.Cookie do
  @moduledoc """
  Cookie + CSRF authentication for UniFi controllers.

  Use this when the controller does not expose API-key auth (Cloud Key,
  older UniFi OS releases) or when you need access to the legacy
  `/api/s/{site}/...` and `/v2/api/site/{site}/...` endpoints, which
  Ubiquiti has not exposed under `x-api-key`.

  ## Quick start

      client = UnifiApi.new(base_url: "https://192.168.1.1", verify_ssl: false)

      {:ok, authed} =
        UnifiApi.Auth.Cookie.login(client, "admin", "password",
          style: :udm  # or :cloud_key
        )

      # `authed` is a Req.Request with session cookies and CSRF token baked in.
      # Pass it to any UnifiApi.Network or UnifiApi.Protect module.
      UnifiApi.Network.Sites.list(authed)

  ## Style selection

  Controllers use one of two login flows. Pass `:style` explicitly, or use
  `UnifiApi.detect/1` first and read the `:auth_path` field.

  | Style | Login path | Auth header source |
  |-------|------------|---------------------|
  | `:udm` (UDM / UDM Pro / UDM SE / UCK-G2) | `POST /api/auth/login` | `X-CSRF-Token` response header |
  | `:cloud_key` (Cloud Key, standalone) | `POST /api/login` | `csrf_token` cookie |

  ## CSRF rotation

  UniFi controllers may rotate the CSRF token mid-session. The token captured
  at login is baked into the returned `Req.Request.t()` and is **not**
  automatically refreshed. For long-running pollers that perform writes:

    * Read-only requests (GET) work indefinitely — CSRF is only enforced on
      mutating verbs.
    * If a write returns 403, call `refresh_csrf/1` (issues a lightweight GET
      and updates the token from the response header) or simply call
      `login/4` again.

  This is a deliberate trade-off in v0.3.0 to keep authenticated sessions
  stateless. A supervised auto-refreshing session may follow in a later
  release.

  > **Note:** This module is implemented to the documented and observed
  > shape of the UniFi login endpoints. It has been unit-tested against
  > mocked `Req.Test` plugs but not yet end-to-end against a live UDM Pro
  > or Cloud Key. Please file an issue with the controller model and
  > firmware version if you encounter shape mismatches.
  """

  alias UnifiApi.AuthError

  @type style :: :udm | :cloud_key

  @doc """
  Authenticates against the controller and returns a session-bearing client.

  ## Options

    * `:style` — `:udm` (default) or `:cloud_key`. Selects the login path.
    * `:remember` — for `:cloud_key`, sets the `remember` flag on the login
      payload (default: `false`).

  ## Returns

    * `{:ok, %Req.Request{}}` — the request struct has session cookies in
      its headers and the captured CSRF token under
      `:private.unifi_api_csrf` so subsequent calls can replay it.
    * `{:error, %UnifiApi.AuthError{}}` — credentials rejected (HTTP 401/403).
    * `{:error, term()}` — transport or unexpected response.
  """
  @spec login(Req.Request.t(), String.t(), String.t(), keyword()) ::
          {:ok, Req.Request.t()} | {:error, term()}
  def login(client, username, password, opts \\ []) do
    style = Keyword.get(opts, :style, :udm)
    remember = Keyword.get(opts, :remember, false)
    body = build_login_body(style, username, password, remember)
    path = login_path(style)

    case Req.post(client, url: path, json: body) do
      {:ok, %Req.Response{status: 200} = resp} ->
        {:ok, install_session(client, resp, style)}

      {:ok, %Req.Response{status: status, body: body}} when status in [401, 403] ->
        reason = if status == 401, do: :unauthorized, else: :forbidden
        {:error, %AuthError{status: status, reason: reason, body: body}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Logs out and invalidates the controller-side session.

  Best-effort — the client struct is not modified, since `Req.Request` is
  not mutated in place. Discard the request after calling this.
  """
  @spec logout(Req.Request.t(), keyword()) :: :ok | {:error, term()}
  def logout(client, opts \\ []) do
    style = Keyword.get(opts, :style, :udm)
    path = if style == :udm, do: "/api/auth/logout", else: "/api/logout"

    case Req.post(client, url: path, json: %{}) do
      {:ok, _resp} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Refreshes the CSRF token by issuing a lightweight GET and capturing the
  rotated token from the response header.

  Useful when a mutating call has returned 403 due to CSRF expiry and you
  want to retry without a full re-login.

  Returns a new `Req.Request.t()` with the refreshed token; the original
  is unchanged.
  """
  @spec refresh_csrf(Req.Request.t(), keyword()) :: {:ok, Req.Request.t()} | {:error, term()}
  def refresh_csrf(client, opts \\ []) do
    probe_path = Keyword.get(opts, :probe_path, "/")

    case Req.get(client, url: probe_path) do
      {:ok, %Req.Response{} = resp} ->
        case extract_csrf(resp) do
          nil -> {:ok, client}
          token -> {:ok, put_csrf(client, token)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the CSRF token currently stored on the client, if any.
  """
  @spec csrf_token(Req.Request.t()) :: String.t() | nil
  def csrf_token(%Req.Request{private: private}) do
    Map.get(private, :unifi_api_csrf)
  end

  defp build_login_body(:udm, user, pass, _remember),
    do: %{username: user, password: pass}

  defp build_login_body(:cloud_key, user, pass, remember),
    do: %{username: user, password: pass, remember: remember}

  defp login_path(:udm), do: "/api/auth/login"
  defp login_path(:cloud_key), do: "/api/login"

  defp install_session(client, %Req.Response{} = resp, _style) do
    cookies = extract_cookies(resp)
    csrf = extract_csrf(resp) || extract_csrf_from_cookies(cookies)

    client
    |> put_cookies(cookies)
    |> put_csrf(csrf)
  end

  defp put_cookies(client, []), do: client

  defp put_cookies(client, cookies) do
    cookie_header =
      cookies
      |> Enum.map(fn {name, value} -> "#{name}=#{value}" end)
      |> Enum.join("; ")

    Req.Request.put_header(client, "cookie", cookie_header)
  end

  defp put_csrf(client, nil), do: client

  defp put_csrf(client, token) do
    client
    |> Req.Request.put_header("x-csrf-token", token)
    |> Req.Request.put_private(:unifi_api_csrf, token)
  end

  # Parses Set-Cookie headers into a list of {name, value} tuples.
  # Discards Path / Domain / Secure / HttpOnly / SameSite attributes.
  defp extract_cookies(%Req.Response{} = resp) do
    resp
    |> Req.Response.get_header("set-cookie")
    |> Enum.map(&parse_set_cookie/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_set_cookie(set_cookie) when is_binary(set_cookie) do
    case String.split(set_cookie, ";", parts: 2) do
      [pair | _] ->
        case String.split(pair, "=", parts: 2) do
          [name, value] -> {String.trim(name), String.trim(value)}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_csrf(%Req.Response{} = resp) do
    case Req.Response.get_header(resp, "x-csrf-token") do
      [token | _] -> token
      _ -> nil
    end
  end

  defp extract_csrf_from_cookies(cookies) do
    Enum.find_value(cookies, fn
      {"csrf_token", value} -> value
      _ -> nil
    end)
  end
end
