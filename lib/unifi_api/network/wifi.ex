defmodule UnifiApi.Network.Wifi do
  @moduledoc """
  UniFi Network API — WiFi broadcasts.

  Lists WiFi SSID configurations on a site.
  """

  use UnifiApi.Resource, api: :network

  @doc """
  Lists all WiFi broadcasts (SSIDs) on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, ssids} = UnifiApi.Network.Wifi.list(client, site_id)
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/wifi/broadcasts",
      opts
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates through all WiFi broadcasts.

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

      # The error tuple, when present, is the *last* element — never the head.
      ssids = UnifiApi.Network.Wifi.stream(client, site_id) |> Enum.to_list()

      case List.last(ssids) do
        {:error, error, offset} -> {:error, error, offset}
        _ -> {:ok, ssids}
      end

      # Or opt into raising, and the enumerable is homogeneous:
      UnifiApi.Network.Wifi.stream(client, site_id, raise_errors: true)
      |> Enum.map(& &1["name"])
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    Client.stream(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/wifi/broadcasts",
      opts
    )
  end
end
