defmodule UnifiApi.Network.RogueAP do
  @moduledoc """
  UniFi Network API (v1) — neighbouring / rogue access points.

  Returns APs the site's UniFi APs have observed broadcasting nearby —
  possibly your own (cooperating multi-controller setups), unmanaged
  networks, or genuinely rogue APs.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Rogue AP fields

    * `_id`, `bssid`, `essid`, `band`, `channel`
    * `freq`, `signal`, `noise`, `rssi`, `security`
    * `is_rogue` — boolean (operator override)
    * `is_adhoc`, `is_ubnt`
    * `last_seen`, `report_time`
    * `ap_mac`, `ap_name` — the local AP that saw it
  """

  use UnifiApi.Resource, api: :network_v1

  @doc """
  Lists active (currently visible) rogue / neighbouring APs.

  ## Options

  Validated with `Keyword.validate!/2` — an unknown key raises
  `ArgumentError` rather than being silently dropped.

    * `:limit` — page size, sent as the v1 `_limit` query param.
    * `:start` — page offset, sent as the v1 `_start` query param.
    * `:params` — extra query params, merged verbatim ahead of
      `_limit` / `_start`.
    * `:raw` — when `true`, return the raw response body binary (skips
      JSON decoding and the v1 envelope unwrap).

  ## Pagination — first page only, and there is no `stream/3`

  `/stat/rogueap` is a v1 collection endpoint: it pages on
  `_start` / `_limit` and the `meta` envelope carries no total count, so a
  full page is indistinguishable from a truncated one. `list/3` returns
  **the first page only** whenever `:limit` is set, and whatever the
  controller's own default cap allows otherwise. This matters here more
  than on most v1 endpoints: a dense RF environment routinely produces
  hundreds of neighbouring BSSIDs, so a rogue-AP sweep that reads one page
  and stops can silently miss the AP it is looking for. There is **no
  `stream/3`** — page manually with `limit: n` and `:start` in steps of
  `n` until a page returns fewer than `n` items.

  ## Examples

      {:ok, aps} = UnifiApi.Network.RogueAP.list(authed, "default")

      # Walk a busy site 200 at a time
      {:ok, page_2} = UnifiApi.Network.RogueAP.list(authed, "default",
        limit: 200, start: 200)
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, [:limit, :start, :params, :raw])

    Client.get_v1(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/stat/rogueap",
      request_opts(opts)
    )
  end

  @doc """
  Lists APs the operator has explicitly acknowledged / known-listed.

  ## Options

  Same as `list/3` — `:limit`, `:start`, `:params`, `:raw`, validated with
  `Keyword.validate!/2`.

  ## Pagination — first page only, and there is no `stream/3`

  `/rest/rogueknown` pages on `_start` / `_limit` like every v1 collection
  and reports no total count, so `list_known/3` returns **the first page
  only**. The known-list is operator-curated and therefore short in
  practice; page manually with `:limit` / `:start` if yours is not.

  ## Examples

      {:ok, known} = UnifiApi.Network.RogueAP.list_known(authed, "default")
  """
  @spec list_known(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list_known(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, [:limit, :start, :params, :raw])

    Client.get_v1(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/rest/rogueknown",
      request_opts(opts)
    )
  end

  # Both endpoints take the identical v1 paging shape, so the `_limit` /
  # `_start` mapping lives in one place.
  defp request_opts(opts) do
    params =
      opts
      |> Keyword.get(:params, [])
      |> maybe_param(:_limit, opts[:limit])
      |> maybe_param(:_start, opts[:start])

    Keyword.take(opts, [:raw]) ++ [params: params]
  end
end
