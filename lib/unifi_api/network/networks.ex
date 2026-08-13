defmodule UnifiApi.Network.Networks do
  @moduledoc """
  UniFi Network API — network configuration.

  Create, read, update, and delete network configurations (VLANs, subnets, etc.)
  on a site.
  """

  use UnifiApi.Resource, api: :network

  @doc """
  Lists all networks on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, networks} = UnifiApi.Network.Networks.list(client, site_id)
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/networks", opts)
  end

  @doc """
  Gets a specific network by ID.

  ## Examples

      {:ok, network} = UnifiApi.Network.Networks.get(client, site_id, network_id)
      network["name"]   # => "LAN"
      network["vlanId"] # => 1
  """
  @spec get(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get(client, site_id, network_id) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/networks/#{id!(network_id)}"
    )
  end

  @doc """
  Creates a new network on a site.

  ## Examples

      {:ok, network} = UnifiApi.Network.Networks.create(client, site_id, %{
        name: "Guest VLAN",
        vlanId: 100
      })
  """
  @spec create(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def create(client, site_id, body) do
    Client.post(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/networks", body)
  end

  @doc """
  Updates an existing network.

  ## Examples

      {:ok, _} = UnifiApi.Network.Networks.update(client, site_id, network_id, %{
        name: "Updated Network Name"
      })
  """
  @spec update(Req.Request.t(), String.t(), String.t(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def update(client, site_id, network_id, body) do
    Client.put(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/networks/#{id!(network_id)}",
      body
    )
  end

  @doc """
  Deletes a network.

  ## Examples

      {:ok, _} = UnifiApi.Network.Networks.delete(client, site_id, network_id)
  """
  @spec delete(Req.Request.t(), String.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def delete(client, site_id, network_id, opts \\ []) do
    Client.delete(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/networks/#{id!(network_id)}",
      opts
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates through all networks on a site.

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

      UnifiApi.Network.Networks.stream(client, site_id, raise_errors: true)
      |> Enum.map(& &1["name"])
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/networks", opts)
  end
end
