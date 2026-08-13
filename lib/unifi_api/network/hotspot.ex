defmodule UnifiApi.Network.Hotspot do
  @moduledoc """
  UniFi Network API — hotspot voucher management.

  Create, list, and delete guest access vouchers.

  ## Voucher fields

    * `id`, `name`, `code`
    * `createdAt`, `activatedAt`, `expiresAt`, `expired`
    * `authorizedGuestLimit`, `authorizedGuestCount`
    * `timeLimitMinutes`, `dataUsageLimitMBytes`
    * `rxRateLimitKbps`, `txRateLimitKbps`
  """

  use UnifiApi.Resource, api: :network

  @doc """
  Lists all hotspot vouchers on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, vouchers} = UnifiApi.Network.Hotspot.list_vouchers(client, site_id)
  """
  @spec list_vouchers(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list_vouchers(client, site_id, opts \\ []) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/hotspot/vouchers",
      opts
    )
  end

  @doc """
  Gets a specific voucher by ID.

  ## Examples

      {:ok, voucher} = UnifiApi.Network.Hotspot.get_voucher(client, site_id, voucher_id)
      voucher["code"]    # => "12345-67890"
      voucher["expired"] # => false
  """
  @spec get_voucher(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get_voucher(client, site_id, voucher_id) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/hotspot/vouchers/#{id!(voucher_id)}"
    )
  end

  @doc """
  Creates one or more vouchers (1-1000 at a time).

  ## Body fields

    * `count` — number of vouchers to create (1-1000, required)
    * `name` — voucher label
    * `timeLimitMinutes` — session duration
    * `authorizedGuestLimit` — max guests per voucher
    * `dataUsageLimitMBytes` — data cap
    * `rxRateLimitKbps` — download speed limit
    * `txRateLimitKbps` — upload speed limit

  ## Examples

      {:ok, vouchers} = UnifiApi.Network.Hotspot.create_vouchers(client, site_id, %{
        count: 10,
        name: "Event Pass",
        timeLimitMinutes: 1440,
        authorizedGuestLimit: 1,
        dataUsageLimitMBytes: 500,
        rxRateLimitKbps: 5000,
        txRateLimitKbps: 1000
      })
  """
  @spec create_vouchers(Req.Request.t(), String.t(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def create_vouchers(client, site_id, body) do
    Client.post(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/hotspot/vouchers",
      body
    )
  end

  @doc """
  Deletes all vouchers on a site.

  ## Examples

      {:ok, _} = UnifiApi.Network.Hotspot.delete_vouchers(client, site_id)
  """
  @spec delete_vouchers(Req.Request.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def delete_vouchers(client, site_id) do
    Client.delete(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/hotspot/vouchers")
  end

  @doc """
  Deletes a specific voucher.

  ## Examples

      {:ok, _} = UnifiApi.Network.Hotspot.delete_voucher(client, site_id, voucher_id)
  """
  @spec delete_voucher(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def delete_voucher(client, site_id, voucher_id) do
    Client.delete(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/hotspot/vouchers/#{id!(voucher_id)}"
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates through all vouchers.

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

      # Get all active voucher codes
      UnifiApi.Network.Hotspot.stream_vouchers(client, site_id, raise_errors: true)
      |> Stream.reject(& &1["expired"])
      |> Enum.map(& &1["code"])
  """
  @spec stream_vouchers(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream_vouchers(client, site_id, opts \\ []) do
    Client.stream(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/hotspot/vouchers",
      opts
    )
  end
end
