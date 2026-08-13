defmodule UnifiApi.RateLimitError do
  @moduledoc """
  Returned when the controller responds with HTTP 429.

  The `:retry_after` field is parsed from the `Retry-After` response header.
  Both seconds (integer) and HTTP-date forms are supported. Defaults to 60
  seconds if absent or unparseable, and is clamped to the range 1..300.

  The raw response `:body` is **not** stored — it can leak sensitive
  details via `Inspect`/`Logger`/Sentry. A scrubbed, truncated
  `:body_preview` (URL/host-like patterns redacted, ≤ 128 chars) is
  provided for diagnostics. See `UnifiApi.Client.scrub_body_preview/1`.

  ## Example

      case UnifiApi.Network.Clients.list(client, site_id) do
        {:ok, clients} ->
          handle(clients)

        {:error, %UnifiApi.RateLimitError{retry_after: seconds}} ->
          Process.sleep(seconds * 1000)
          retry()
      end
  """

  defexception [:retry_after, :status, :body_preview]

  @type t :: %__MODULE__{
          retry_after: pos_integer(),
          status: 429,
          body_preview: binary() | nil
        }

  @impl true
  def message(%__MODULE__{retry_after: seconds}),
    do: "rate limited by controller (HTTP 429); retry after #{seconds}s"
end

defmodule UnifiApi.AuthError do
  @moduledoc """
  Returned when the controller responds with HTTP 401 or 403.

  The raw response `:body` is **not** stored — it can leak sensitive
  details via `Inspect`/`Logger`/Sentry. A scrubbed, truncated
  `:body_preview` (URL/host-like patterns redacted, ≤ 128 chars) is
  provided for diagnostics. See `UnifiApi.Client.scrub_body_preview/1`.

  ## Example

      case UnifiApi.Network.Sites.list(client) do
        {:ok, sites} ->
          handle(sites)

        {:error, %UnifiApi.AuthError{reason: :unauthorized}} ->
          # API key invalid or expired
          :reauth

        {:error, %UnifiApi.AuthError{reason: :forbidden}} ->
          # API key valid but lacks permission for this resource
          :no_access
      end
  """

  defexception [:status, :body_preview, :reason]

  @type reason :: :unauthorized | :forbidden
  @type t :: %__MODULE__{
          status: 401 | 403,
          body_preview: binary() | nil,
          reason: reason()
        }

  @impl true
  def message(%__MODULE__{reason: :unauthorized}),
    do: "unauthorized (HTTP 401): missing or invalid credentials"

  def message(%__MODULE__{reason: :forbidden}),
    do: "forbidden (HTTP 403): credentials lack permission for this resource"
end

defmodule UnifiApi.ApiError do
  @moduledoc """
  Returned for a controller response that failed but is not an
  authentication (401/403) or rate-limit (429) failure.

  Two situations produce it:

    * **A non-2xx HTTP status** — `:status` is that status and `:code` is
      `nil`.
    * **A v1 envelope error** — the legacy `/api/s/...` endpoints answer
      `200 OK` carrying `%{"meta" => %{"rc" => "error", "msg" => code}}`.
      `:status` is then the HTTP status (normally `200`) and `:code` is the
      controller's error code, e.g. `"api.err.LoginRequired"`.

  As with the other error structs the raw body is **not** retained; see
  `UnifiApi.Client.scrub_body_preview/1`.

  ## Example

      case UnifiApi.Network.Networks.create(client, site_id, params) do
        {:ok, network} ->
          handle(network)

        {:error, %UnifiApi.ApiError{status: 409}} ->
          :conflict

        {:error, %UnifiApi.ApiError{code: "api.err.LoginRequired"}} ->
          :session_expired
      end
  """

  defexception [:status, :code, :body_preview]

  @type t :: %__MODULE__{
          status: non_neg_integer() | nil,
          code: String.t() | nil,
          body_preview: binary() | nil
        }

  @impl true
  def message(%__MODULE__{code: code, status: status}) when is_binary(code),
    do: "controller returned error #{code} (HTTP #{status || "?"})"

  def message(%__MODULE__{status: status}),
    do: "controller returned HTTP #{status}"
end

defmodule UnifiApi.TransportError do
  @moduledoc """
  Returned when the request never produced an HTTP response: connection
  refused, DNS failure, TLS handshake failure, timeout, and so on.

  This wraps the underlying `Req.TransportError` / `Req.HTTPError` (or any
  other term the adapter surfaced) so that consumers can write one
  exhaustive `case` over `t:UnifiApi.Error.t/0` without matching on Req's
  structs. The original is preserved in `:original` for debugging.

  ## Example

      case UnifiApi.Network.Sites.list(client) do
        {:ok, sites} -> handle(sites)
        {:error, %UnifiApi.TransportError{reason: :econnrefused}} -> :controller_down
        {:error, %UnifiApi.TransportError{reason: :timeout}} -> :slow
      end
  """

  defexception [:reason, :original]

  @type t :: %__MODULE__{reason: atom() | term(), original: term()}

  @impl true
  def message(%__MODULE__{reason: reason}),
    do: "transport failure before any HTTP response: #{inspect(reason)}"
end

defmodule UnifiApi.Error do
  @moduledoc """
  The error umbrella.

  Every failure this library reports is one of the structs in
  `t:t/0`. Before v0.4.0 there were ten different ad-hoc shapes — bare
  `{status, body}` tuples, `{:unifi_error, msg}`, `{:unexpected_status,
  status, body}`, raw `Req` structs — so a consumer could not write an
  exhaustive `case`, and every new shape was an invisible breaking change.

  A handful of functions additionally return a documented plain atom for a
  non-error outcome that is not a controller failure
  (`UnifiApi.Network.Sites.find_by_name/2` returns `:not_found`,
  `UnifiApi.Auth.Cookie.logout/2` returns `:not_logged_in`). Those are
  named in the individual `@spec`s rather than folded in here.

  ## Exhaustive handling

      case UnifiApi.Network.Clients.list(client, site_id) do
        {:ok, clients} -> {:ok, clients}
        {:error, %UnifiApi.AuthError{}} -> :reauth
        {:error, %UnifiApi.RateLimitError{retry_after: s}} -> {:backoff, s}
        {:error, %UnifiApi.ApiError{status: status}} -> {:api, status}
        {:error, %UnifiApi.TransportError{reason: reason}} -> {:transport, reason}
      end

  `UnifiApi.StreamError` only appears from the `stream/*` functions — as the
  `{:error, reason, cursor}` stream tail, or raised under
  `raise_errors: true`.
  """

  @typedoc "Any error this library returns."
  @type t ::
          UnifiApi.AuthError.t()
          | UnifiApi.RateLimitError.t()
          | UnifiApi.ApiError.t()
          | UnifiApi.TransportError.t()
          | UnifiApi.StreamError.t()

  @doc """
  Wraps a transport-layer failure term in `UnifiApi.TransportError`.

  Passes any error already inside the umbrella through unchanged, so it is
  safe to call on the `{:error, reason}` of a nested request.
  """
  @spec from_transport(term()) :: t()
  def from_transport(%UnifiApi.TransportError{} = error), do: error
  def from_transport(%UnifiApi.AuthError{} = error), do: error
  def from_transport(%UnifiApi.RateLimitError{} = error), do: error
  def from_transport(%UnifiApi.ApiError{} = error), do: error
  def from_transport(%UnifiApi.StreamError{} = error), do: error

  def from_transport(%{__exception__: true, reason: reason} = original),
    do: %UnifiApi.TransportError{reason: reason, original: original}

  def from_transport(reason), do: %UnifiApi.TransportError{reason: reason, original: reason}
end
