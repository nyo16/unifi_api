defmodule UnifiApi.Network.DNS do
  @moduledoc """
  UniFi Network API — DNS policy management.

  Create and manage DNS records and forwarding rules.

  ## Supported record types

    * `A_RECORD` — IPv4 address mapping
    * `AAAA_RECORD` — IPv6 address mapping
    * `CNAME_RECORD` — canonical name alias
    * `MX_RECORD` — mail exchange
    * `TXT_RECORD` — text record
    * `SRV_RECORD` — service locator
    * `FORWARD_DOMAIN` — domain forwarding
  """

  alias UnifiApi.Client

  @doc """
  Lists all DNS policies on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, policies} = UnifiApi.Network.DNS.list(client, site_id)
  """
  @spec list(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/dns/policies", opts)
  end

  @doc """
  Gets a specific DNS policy.

  ## Examples

      {:ok, policy} = UnifiApi.Network.DNS.get(client, site_id, policy_id)
  """
  @spec get(Req.Request.t(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(client, site_id, policy_id) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/dns/policies/#{policy_id}")
  end

  @doc """
  Creates a new DNS policy.

  ## Examples

      # A record
      {:ok, _} = UnifiApi.Network.DNS.create(client, site_id, %{
        type: "A_RECORD",
        name: "app.local",
        value: "192.168.1.50"
      })

      # CNAME record
      {:ok, _} = UnifiApi.Network.DNS.create(client, site_id, %{
        type: "CNAME_RECORD",
        name: "www.local",
        value: "app.local"
      })
  """
  @spec create(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def create(client, site_id, body) do
    Client.post(client, "#{prefix()}/v1/sites/#{site_id}/dns/policies", body)
  end

  @doc """
  Updates an existing DNS policy.

  ## Examples

      {:ok, _} = UnifiApi.Network.DNS.update(client, site_id, policy_id, %{
        value: "192.168.1.51"
      })
  """
  @spec update(Req.Request.t(), String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def update(client, site_id, policy_id, body) do
    Client.put(client, "#{prefix()}/v1/sites/#{site_id}/dns/policies/#{policy_id}", body)
  end

  @doc """
  Deletes a DNS policy.

  ## Examples

      {:ok, _} = UnifiApi.Network.DNS.delete(client, site_id, policy_id)
  """
  @spec delete(Req.Request.t(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def delete(client, site_id, policy_id) do
    Client.delete(client, "#{prefix()}/v1/sites/#{site_id}/dns/policies/#{policy_id}")
  end

  @doc """
  Returns a lazy stream that auto-paginates through all DNS policies.

  ## Examples

      UnifiApi.Network.DNS.stream(client, site_id)
      |> Enum.group_by(& &1["type"])
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sites/#{site_id}/dns/policies", opts)
  end

  defp prefix, do: Client.network_prefix()
end
