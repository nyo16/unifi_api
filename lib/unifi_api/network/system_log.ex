defmodule UnifiApi.Network.SystemLog do
  @moduledoc """
  UniFi Network API (v2) — system log.

  Returns the controller's structured system log: device adoption,
  firmware updates, gateway events, threat-management actions, etc. This
  is more focused than `UnifiApi.Network.Events` — events covers all
  client/AP activity, system log covers controller-level operations.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Common entry fields

    * `id`, `timestamp`, `category`, `level`
    * `key`, `subsystem`
    * `description` — human-readable message
    * `device` — when the log line is device-attributed
  """

  alias UnifiApi.Client

  @doc """
  Returns all system log entries within the supported window.

  ## Options

    * `:limit` — server-side cap (`pageSize` query param).
    * `:start` — bucket start (`pageNumber` query param).
  """
  @spec list_all(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_all(client, site_id, opts \\ []) do
    params =
      []
      |> maybe_param(:pageSize, opts[:limit])
      |> maybe_param(:pageNumber, opts[:start])

    Client.get_v1(client, "#{prefix()}/v2/api/site/#{site_id}/system-log/all", params: params)
  end

  @doc """
  Returns a lazy stream that auto-paginates the system log via
  `pageSize` / `pageNumber`.

  ## Options

    * `:limit` — page size (default 500).
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    page_size = opts[:limit] || 500
    path = "#{prefix()}/v2/api/site/#{site_id}/system-log/all"

    Client.stream_paged(
      fn page ->
        Client.get_v1(client, path, params: [pageSize: page_size, pageNumber: page])
      end,
      limit: page_size
    )
  end

  defp maybe_param(params, _key, nil), do: params
  defp maybe_param(params, key, value), do: [{key, value} | params]

  defp prefix, do: Client.v1_prefix()
end
