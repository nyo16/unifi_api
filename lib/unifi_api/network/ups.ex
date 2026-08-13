defmodule UnifiApi.Network.UPS do
  @moduledoc """
  UniFi Network API (v1) — UPS devices.

  Returns connected UPS units (typically attached to a UDM Pro via USB)
  with battery, runtime, and load telemetry.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## UPS fields

    * `name`, `model`, `serial`
    * `ups_status` — `"OL"` (online), `"OB"` (on battery), `"LB"` (low
      battery)
    * `battery_charge` (0..100 percent), `battery_runtime` (seconds)
    * `input_voltage`, `output_voltage`
    * `load_pct`
  """

  use UnifiApi.Resource, api: :network_v1

  @doc """
  Lists connected UPS devices on a site.

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

  `/stat/ups-devices` is a v1 collection endpoint: it pages on
  `_start` / `_limit` and the `meta` envelope carries no total count, so a
  full page is indistinguishable from a truncated one. `list/3` returns
  **the first page only** whenever `:limit` is set, and whatever the
  controller's own default cap allows otherwise. This module has **no
  `stream/3`** — a site has a handful of UPS units at most, so paging is
  not normally needed. Page manually when it is: request `limit: n` and
  walk `:start` in steps of `n` until a page returns fewer than `n` items.

  ## Examples

      {:ok, upses} = UnifiApi.Network.UPS.list(authed, "default")

      # Explicit first page of 50
      {:ok, upses} = UnifiApi.Network.UPS.list(authed, "default", limit: 50, start: 0)
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, [:limit, :start, :params, :raw])

    params =
      opts
      |> Keyword.get(:params, [])
      |> maybe_param(:_limit, opts[:limit])
      |> maybe_param(:_start, opts[:start])

    Client.get_v1(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/stat/ups-devices",
      Keyword.take(opts, [:raw]) ++ [params: params]
    )
  end
end
