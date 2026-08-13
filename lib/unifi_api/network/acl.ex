defmodule UnifiApi.Network.ACL do
  @moduledoc """
  UniFi Network API — ACL rule management.

  Create, read, update, delete, and reorder access control list rules.

  ## ACL rule fields

    * `type` — `"IPV4"` or `"MAC"`
    * `id`, `name`, `description`, `enabled`, `index`
    * `action` — `"ALLOW"` or `"BLOCK"`
    * `enforcingDeviceFilter`, `sourceFilter`, `destinationFilter`
    * `protocolFilter`, `networkId`, `metadata`
  """

  use UnifiApi.Resource, api: :network

  @doc """
  Lists all ACL rules on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, rules} = UnifiApi.Network.ACL.list(client, site_id)
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/acl-rules", opts)
  end

  @doc """
  Gets a specific ACL rule.

  ## Examples

      {:ok, rule} = UnifiApi.Network.ACL.get(client, site_id, rule_id)
      rule["action"] # => "BLOCK"
      rule["type"]   # => "IPV4"
  """
  @spec get(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get(client, site_id, rule_id) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/acl-rules/#{id!(rule_id)}"
    )
  end

  @doc """
  Creates a new ACL rule.

  ## Examples

      {:ok, rule} = UnifiApi.Network.ACL.create(client, site_id, %{
        type: "IPV4",
        name: "Block SSH",
        enabled: true,
        action: "BLOCK",
        protocolFilter: %{protocol: "TCP", dstPort: 22}
      })
  """
  @spec create(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def create(client, site_id, body) do
    Client.post(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/acl-rules", body)
  end

  @doc """
  Updates an existing ACL rule.

  ## Examples

      {:ok, _} = UnifiApi.Network.ACL.update(client, site_id, rule_id, %{enabled: false})
  """
  @spec update(Req.Request.t(), String.t(), String.t(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def update(client, site_id, rule_id, body) do
    Client.put(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/acl-rules/#{id!(rule_id)}",
      body
    )
  end

  @doc """
  Deletes an ACL rule.

  ## Examples

      {:ok, _} = UnifiApi.Network.ACL.delete(client, site_id, rule_id)
  """
  @spec delete(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def delete(client, site_id, rule_id) do
    Client.delete(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/acl-rules/#{id!(rule_id)}"
    )
  end

  @doc """
  Gets the current ACL rule ordering.

  ## Examples

      {:ok, ordering} = UnifiApi.Network.ACL.get_ordering(client, site_id)
      # => %{"ids" => ["rule-1", "rule-2", "rule-3"]}
  """
  @spec get_ordering(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get_ordering(client, site_id) do
    Client.get(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/acl-rules/ordering")
  end

  @doc """
  Updates the ACL rule ordering.

  ## Examples

      {:ok, _} = UnifiApi.Network.ACL.update_ordering(client, site_id, %{
        ids: ["rule-3", "rule-1", "rule-2"]
      })
  """
  @spec update_ordering(Req.Request.t(), String.t(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def update_ordering(client, site_id, body) do
    Client.put(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/acl-rules/ordering",
      body
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates through all ACL rules.

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

      UnifiApi.Network.ACL.stream(client, site_id, raise_errors: true)
      |> Stream.filter(& &1["enabled"])
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/acl-rules", opts)
  end
end
