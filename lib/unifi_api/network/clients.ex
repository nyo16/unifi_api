defmodule UnifiApi.Network.Clients do
  @moduledoc """
  UniFi Network API — connected clients.

  Lists currently connected clients with their connection type, IP address,
  and other details.
  """

  alias UnifiApi.Client

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
  @spec list(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/clients", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all clients on a site.

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression

  ## Examples

      # Stream all wireless clients
      UnifiApi.Network.Clients.stream(client, site_id, filter: "type.eq(WIRELESS)")
      |> Enum.to_list()

      # Count all connected clients
      UnifiApi.Network.Clients.stream(client, site_id)
      |> Enum.count()
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sites/#{site_id}/clients", opts)
  end

  defp prefix, do: Client.network_prefix()
end
