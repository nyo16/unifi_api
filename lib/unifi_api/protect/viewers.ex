defmodule UnifiApi.Protect.Viewers do
  @moduledoc """
  UniFi Protect API — viewer management.

  List, view, and update Protect viewport devices.

  ## Response fields

    * `id`, `modelKey`, `name`, `mac`
    * `state` — `"CONNECTED"`, `"CONNECTING"`, or `"DISCONNECTED"`
    * `liveview` — the assigned liveview ID
    * `streamLimit` — max concurrent streams
  """

  use UnifiApi.Resource, api: :protect

  @doc """
  Lists viewers.

  ## Options

  Validated with `Keyword.validate!/2` — an unknown key raises
  `ArgumentError` rather than being silently dropped. Forwarded to
  `UnifiApi.Client.get/3`:

    * `:limit` — page size (controller default: 25, max: 200)
    * `:offset` — page offset (default: 0)
    * `:filter` — UniFi filter expression
    * `:params` — extra query params, merged verbatim
    * `:raw` — when `true`, skip JSON decoding and return the raw
      response body binary

  ## Pagination — first page only, and there is no `stream/2`

  The endpoint is paginated and the response carries no total count and no
  cursor, so a full page is indistinguishable from a truncated one.
  `list/2` returns **the first page only**. Unlike `UnifiApi.Protect.Lights`
  or `UnifiApi.Protect.Sensors`, this module has **no `stream/2`** —
  viewport counts are small enough that a single explicit page is normally
  the whole set. Page manually when it is not: request `limit: n` and walk
  `:offset` in steps of `n` until a page comes back with fewer than `n`
  items.

  ## Examples

      {:ok, viewers} = UnifiApi.Protect.Viewers.list(client)

      # Manual pagination — a short page is the last page
      Stream.unfold(0, fn
        nil ->
          nil

        offset ->
          {:ok, page} = UnifiApi.Protect.Viewers.list(client, limit: 200, offset: offset)
          if length(page) < 200, do: {page, nil}, else: {page, offset + 200}
      end)
      |> Enum.concat()
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, opts \\ []) do
    opts = Keyword.validate!(opts, [:limit, :offset, :filter, :params, :raw])

    Client.get(client, "#{prefix(client)}/v1/viewers", opts)
  end

  @doc """
  Gets a specific viewer by ID.

  ## Examples

      {:ok, viewer} = UnifiApi.Protect.Viewers.get(client, viewer_id)
      viewer["name"]  # => "Office Display"
      viewer["state"] # => "CONNECTED"
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get(client, id) do
    Client.get(client, "#{prefix(client)}/v1/viewers/#{id!(id)}")
  end

  @doc """
  Updates viewer settings.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Viewers.update(client, viewer_id, %{
        liveview: liveview_id
      })
  """
  @spec update(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def update(client, id, body) do
    Client.patch(client, "#{prefix(client)}/v1/viewers/#{id!(id)}", body)
  end
end
