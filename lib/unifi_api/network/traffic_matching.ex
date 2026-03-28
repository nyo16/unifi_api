defmodule UnifiApi.Network.TrafficMatching do
  @moduledoc """
  UniFi Network API — traffic matching lists.

  Lists available traffic matching definitions used in firewall and ACL rules.

  ## Types

    * `PORTS` — port-based matching
    * `IPV4_ADDRESSES` — IPv4 address matching
    * `IPV6_ADDRESSES` — IPv6 address matching
  """

  alias UnifiApi.Client

  @doc """
  Lists all traffic matching lists on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, lists} = UnifiApi.Network.TrafficMatching.list(client, site_id)
      # => [%{"id" => "...", "type" => "PORTS", "name" => "HTTP/HTTPS"}]
  """
  @spec list(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/traffic-matching-lists", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all traffic matching lists.

  ## Examples

      UnifiApi.Network.TrafficMatching.stream(client, site_id)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sites/#{site_id}/traffic-matching-lists", opts)
  end

  defp prefix, do: Client.network_prefix()
end
