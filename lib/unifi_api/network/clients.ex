defmodule UnifiApi.Network.Clients do
  @moduledoc """
  UniFi Network API — connected clients.

  Lists currently connected clients with their connection type, IP address,
  and other details.
  """

  use UnifiApi.Resource, api: :network

  @doc """
  Lists all connected clients on a site.

  Each client includes `type` (WIRED, WIRELESS, VPN, or TELEPORT),
  `id`, `name`, `connectedAt`, `ipAddress`, and `access`.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, clients} = UnifiApi.Network.Clients.list(client, site_id)

      # Filter by connection type
      {:ok, wireless} = UnifiApi.Network.Clients.list(client, site_id,
        filter: "type.eq(WIRELESS)"
      )

      # Paginate through all clients
      {:ok, page} = UnifiApi.Network.Clients.list(client, site_id, limit: 50, offset: 0)
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/clients", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all clients on a site.

  ## Error contract

  A mid-stream error does **not** raise by default: the stream halts and
  yields `{:error, %UnifiApi.StreamError{}, last_offset}` as its final
  element, so the enumerable is heterogeneous. Match the tail:

      case Enum.to_list(stream) do
        items when is_list(items) ->
          case List.last(items) do
            {:error, error, cursor} -> {:error, error, cursor}
            _ -> {:ok, items}
          end
      end

  Pass `raise_errors: true` to raise `UnifiApi.StreamError` instead.

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression
    * `:max_pages` — halt after this many successful pages (default: unbounded).
    * `:max_items` — halt once this many items have been yielded (default: unbounded).
    * `:raise_errors` — raise `UnifiApi.StreamError` on error instead of
      yielding the error tuple (default: `false`).

  ## Examples

      # Stream all wireless clients
      UnifiApi.Network.Clients.stream(client, site_id, filter: "type.eq(WIRELESS)")
      |> Enum.to_list()

      # Count all connected clients (an error tail would inflate the count,
      # so raise instead)
      UnifiApi.Network.Clients.stream(client, site_id, raise_errors: true)
      |> Enum.count()
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/clients", opts)
  end
end
