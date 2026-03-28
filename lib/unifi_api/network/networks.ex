defmodule UnifiApi.Network.Networks do
  @moduledoc """
  UniFi Network API — network configuration.

  Create, read, update, and delete network configurations (VLANs, subnets, etc.)
  on a site.
  """

  alias UnifiApi.Client

  @doc """
  Lists all networks on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, networks} = UnifiApi.Network.Networks.list(client, site_id)
  """
  @spec list(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/networks", opts)
  end

  @doc """
  Gets a specific network by ID.

  ## Examples

      {:ok, network} = UnifiApi.Network.Networks.get(client, site_id, network_id)
      network["name"]   # => "LAN"
      network["vlanId"] # => 1
  """
  @spec get(Req.Request.t(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(client, site_id, network_id) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/networks/#{network_id}")
  end

  @doc """
  Creates a new network on a site.

  ## Examples

      {:ok, network} = UnifiApi.Network.Networks.create(client, site_id, %{
        name: "Guest VLAN",
        vlanId: 100
      })
  """
  @spec create(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def create(client, site_id, body) do
    Client.post(client, "#{prefix()}/v1/sites/#{site_id}/networks", body)
  end

  @doc """
  Updates an existing network.

  ## Examples

      {:ok, _} = UnifiApi.Network.Networks.update(client, site_id, network_id, %{
        name: "Updated Network Name"
      })
  """
  @spec update(Req.Request.t(), String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def update(client, site_id, network_id, body) do
    Client.put(client, "#{prefix()}/v1/sites/#{site_id}/networks/#{network_id}", body)
  end

  @doc """
  Deletes a network.

  ## Examples

      {:ok, _} = UnifiApi.Network.Networks.delete(client, site_id, network_id)
  """
  @spec delete(Req.Request.t(), String.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def delete(client, site_id, network_id, opts \\ []) do
    Client.delete(client, "#{prefix()}/v1/sites/#{site_id}/networks/#{network_id}", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all networks on a site.

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression

  ## Examples

      UnifiApi.Network.Networks.stream(client, site_id)
      |> Enum.map(& &1["name"])
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sites/#{site_id}/networks", opts)
  end

  defp prefix, do: Client.network_prefix()
end
