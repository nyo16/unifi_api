defmodule UnifiApi.Network.Sites do
  @moduledoc """
  UniFi Network API — site management.

  Sites are the top-level organizational unit. Most Network API endpoints
  require a `site_id` obtained from this module.
  """

  alias UnifiApi.Client

  @doc """
  Lists all sites on the controller.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, sites} = UnifiApi.Network.Sites.list(client)
      # => [%{"id" => "abc-123", "name" => "Default", "internalReference" => "default"}]

      # Get the default site ID
      {:ok, [site | _]} = UnifiApi.Network.Sites.list(client)
      site_id = site["id"]
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(client, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/sites", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all sites.

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression

  ## Examples

      UnifiApi.Network.Sites.stream(client)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sites", opts)
  end

  defp prefix, do: Client.network_prefix()
end
