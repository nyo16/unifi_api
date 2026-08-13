defmodule UnifiApi.Network.TrafficMatching do
  @moduledoc """
  UniFi Network API — traffic matching lists.

  Lists available traffic matching definitions used in firewall and ACL rules.

  ## Types

    * `PORTS` — port-based matching
    * `IPV4_ADDRESSES` — IPv4 address matching
    * `IPV6_ADDRESSES` — IPv6 address matching
  """

  use UnifiApi.Resource, api: :network

  @doc """
  Lists all traffic matching lists on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, lists} = UnifiApi.Network.TrafficMatching.list(client, site_id)
      # => [%{"id" => "...", "type" => "PORTS", "name" => "HTTP/HTTPS"}]
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/traffic-matching-lists",
      opts
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates through all traffic matching lists.

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

      UnifiApi.Network.TrafficMatching.stream(client, site_id)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    Client.stream(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/traffic-matching-lists",
      opts
    )
  end
end
