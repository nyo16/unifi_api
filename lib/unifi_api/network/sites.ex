defmodule UnifiApi.Network.Sites do
  @moduledoc """
  UniFi Network API — site management.

  Sites are the top-level organizational unit. Most Network API endpoints
  require a `site_id` obtained from this module.
  """

  use UnifiApi.Resource, api: :network

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
  @spec list(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, opts \\ []) do
    Client.get(client, "#{prefix(client)}/v1/sites", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all sites.

  ## Error contract

  A mid-stream error does **not** raise by default: the stream halts and
  yields `{:error, %UnifiApi.StreamError{}, last_offset}` as its final
  element, so the enumerable is heterogeneous and
  `Enum.map(stream, & &1["name"])` crashes on a transient 500. Match the
  tail:

      items = Enum.to_list(stream)

      case List.last(items) do
        {:error, error, cursor} -> {:error, error, cursor}
        _ -> {:ok, items}
      end

  Pass `raise_errors: true` to raise `UnifiApi.StreamError` instead.

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression
    * `:max_pages` — halt after this many successful pages (default:
      unbounded).
    * `:max_items` — halt once this many sites have been yielded (default:
      unbounded).
    * `:raise_errors` — raise `UnifiApi.StreamError` on a mid-stream error
      instead of yielding the error tuple (default: `false`).

  ## Examples

      UnifiApi.Network.Sites.stream(client)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Client.stream(client, "#{prefix(client)}/v1/sites", opts)
  end

  @doc """
  Looks up a site by display name and returns the full site map.

  Saves the boilerplate `Sites.list(client) |> Enum.find(...)` that
  every script wanting a site ID by human-readable name ends up
  writing.

  Matching is exact and case-sensitive. To match the controller's
  internal slug (`internalReference`, e.g. `"default"`) use
  `find_by_internal_reference/2` instead.

  ## Examples

      {:ok, site} = UnifiApi.Network.Sites.find_by_name(client, "HQ")
      site_id = site["id"]

      # When you only care about the id:
      {:ok, %{"id" => site_id}} = UnifiApi.Network.Sites.find_by_name(client, "HQ")
  """
  @spec find_by_name(Req.Request.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | UnifiApi.Error.t()}
  def find_by_name(client, name) when is_binary(name) do
    find_by(client, "name", name)
  end

  @doc """
  Like `find_by_name/2` but matches against the `internalReference`
  field — the controller's internal slug, e.g. `"default"`.
  """
  @spec find_by_internal_reference(Req.Request.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | UnifiApi.Error.t()}
  def find_by_internal_reference(client, ref) when is_binary(ref) do
    find_by(client, "internalReference", ref)
  end

  defp find_by(client, field, value) do
    with {:ok, sites} <- list(client) do
      case Enum.find(sites, &(Map.get(&1, field) == value)) do
        nil -> {:error, :not_found}
        site -> {:ok, site}
      end
    end
  end
end
