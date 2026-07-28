defmodule UnifiApi.RateLimitError do
  @moduledoc """
  Returned when the controller responds with HTTP 429.

  The `:retry_after` field is parsed from the `Retry-After` response header.
  Both seconds (integer) and HTTP-date forms are supported. Defaults to 60
  seconds if absent or unparseable, and is clamped to the range 1..300.

  ## Example

      case UnifiApi.Network.Clients.list(client, site_id) do
        {:ok, clients} ->
          handle(clients)

        {:error, %UnifiApi.RateLimitError{retry_after: seconds}} ->
          Process.sleep(seconds * 1000)
          retry()
      end
  """

  defexception [:retry_after, :status, :body]

  @type t :: %__MODULE__{
          retry_after: pos_integer(),
          status: 429,
          body: term()
        }

  @impl true
  def message(%__MODULE__{retry_after: seconds}) do
    "rate limited by controller (HTTP 429); retry after #{seconds}s"
  end
end

defmodule UnifiApi.AuthError do
  @moduledoc """
  Returned when the controller responds with HTTP 401 or 403.

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

  defexception [:status, :body, :reason]

  @type reason :: :unauthorized | :forbidden
  @type t :: %__MODULE__{
          status: 401 | 403,
          body: term(),
          reason: reason()
        }

  @impl true
  def message(%__MODULE__{reason: :unauthorized}),
    do: "unauthorized (HTTP 401): missing or invalid credentials"

  def message(%__MODULE__{reason: :forbidden}),
    do: "forbidden (HTTP 403): credentials lack permission for this resource"
end
