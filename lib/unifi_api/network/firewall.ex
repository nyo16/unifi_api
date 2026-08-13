defmodule UnifiApi.Network.Firewall do
  @moduledoc """
  UniFi Network API — firewall zones and policies.

  Manage firewall zones (groups of networks) and traffic policies
  (allow/block/reject rules between zones).

  ## Zone fields

    * `id` — zone identifier
    * `name` — display name
    * `networkIds` — list of network IDs in this zone
    * `metadata` — additional metadata

  ## Policy fields

    * `id`, `name`, `description`, `enabled`, `index`
    * `action` — `"ALLOW"`, `"BLOCK"`, or `"REJECT"`
    * `source` — `%{zoneId, trafficFilter}`
    * `destination` — `%{zoneId, trafficFilter}`
    * `ipProtocolScope`, `connectionStateFilter`, `ipsecFilter`
    * `loggingEnabled`, `schedule`, `metadata`
  """

  use UnifiApi.Resource, api: :network

  # --- Zones ---

  @doc """
  Lists all firewall zones on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, zones} = UnifiApi.Network.Firewall.list_zones(client, site_id)
  """
  @spec list_zones(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list_zones(client, site_id, opts \\ []) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/zones",
      opts
    )
  end

  @doc """
  Gets a specific firewall zone.

  ## Examples

      {:ok, zone} = UnifiApi.Network.Firewall.get_zone(client, site_id, zone_id)
      zone["name"]       # => "Internal"
      zone["networkIds"] # => ["net-1", "net-2"]
  """
  @spec get_zone(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get_zone(client, site_id, zone_id) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/zones/#{id!(zone_id)}"
    )
  end

  @doc """
  Creates a new firewall zone.

  ## Examples

      {:ok, zone} = UnifiApi.Network.Firewall.create_zone(client, site_id, %{
        name: "DMZ",
        networkIds: [network_id]
      })
  """
  @spec create_zone(Req.Request.t(), String.t(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def create_zone(client, site_id, body) do
    Client.post(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/zones",
      body
    )
  end

  @doc """
  Updates an existing firewall zone.

  ## Examples

      {:ok, _} = UnifiApi.Network.Firewall.update_zone(client, site_id, zone_id, %{
        name: "DMZ-Updated"
      })
  """
  @spec update_zone(Req.Request.t(), String.t(), String.t(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def update_zone(client, site_id, zone_id, body) do
    Client.put(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/zones/#{id!(zone_id)}",
      body
    )
  end

  @doc """
  Deletes a firewall zone.

  ## Examples

      {:ok, _} = UnifiApi.Network.Firewall.delete_zone(client, site_id, zone_id)
  """
  @spec delete_zone(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def delete_zone(client, site_id, zone_id) do
    Client.delete(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/zones/#{id!(zone_id)}"
    )
  end

  # --- Policies ---

  @doc """
  Lists all firewall policies on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, policies} = UnifiApi.Network.Firewall.list_policies(client, site_id)
  """
  @spec list_policies(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list_policies(client, site_id, opts \\ []) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/policies",
      opts
    )
  end

  @doc """
  Gets a specific firewall policy.

  ## Examples

      {:ok, policy} = UnifiApi.Network.Firewall.get_policy(client, site_id, policy_id)
      policy["action"]  # => "BLOCK"
      policy["enabled"] # => true
  """
  @spec get_policy(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get_policy(client, site_id, policy_id) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/policies/#{id!(policy_id)}"
    )
  end

  @doc """
  Creates a new firewall policy.

  ## Examples

      {:ok, policy} = UnifiApi.Network.Firewall.create_policy(client, site_id, %{
        name: "Block IoT to LAN",
        enabled: true,
        action: "BLOCK",
        source: %{zoneId: iot_zone_id},
        destination: %{zoneId: lan_zone_id}
      })
  """
  @spec create_policy(Req.Request.t(), String.t(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def create_policy(client, site_id, body) do
    Client.post(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/policies",
      body
    )
  end

  @doc """
  Updates an existing firewall policy.

  ## Examples

      {:ok, _} = UnifiApi.Network.Firewall.update_policy(client, site_id, policy_id, %{
        enabled: false
      })
  """
  @spec update_policy(Req.Request.t(), String.t(), String.t(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def update_policy(client, site_id, policy_id, body) do
    Client.put(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/policies/#{id!(policy_id)}",
      body
    )
  end

  @doc """
  Deletes a firewall policy.

  ## Examples

      {:ok, _} = UnifiApi.Network.Firewall.delete_policy(client, site_id, policy_id)
  """
  @spec delete_policy(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def delete_policy(client, site_id, policy_id) do
    Client.delete(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/policies/#{id!(policy_id)}"
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates through all firewall zones.

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

    * `:max_pages` — halt after this many successful pages (default: unbounded).
    * `:max_items` — halt once this many items have been yielded (default: unbounded).
    * `:raise_errors` — raise `UnifiApi.StreamError` on error instead of
      yielding the error tuple (default: `false`).

  ## Examples

      UnifiApi.Network.Firewall.stream_zones(client, site_id, raise_errors: true)
      |> Enum.map(& &1["name"])
  """
  @spec stream_zones(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream_zones(client, site_id, opts \\ []) do
    Client.stream(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/zones",
      opts
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates through all firewall policies.

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

    * `:max_pages` — halt after this many successful pages (default: unbounded).
    * `:max_items` — halt once this many items have been yielded (default: unbounded).
    * `:raise_errors` — raise `UnifiApi.StreamError` on error instead of
      yielding the error tuple (default: `false`).

  ## Examples

      UnifiApi.Network.Firewall.stream_policies(client, site_id, raise_errors: true)
      |> Stream.filter(& &1["enabled"])
      |> Enum.to_list()
  """
  @spec stream_policies(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream_policies(client, site_id, opts \\ []) do
    Client.stream(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/firewall/policies",
      opts
    )
  end
end
