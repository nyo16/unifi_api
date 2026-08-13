defmodule UnifiApi.Network.ActiveLeases do
  @moduledoc """
  UniFi Network API (v2) — active DHCP leases.

  Returns the live DHCP lease table from the gateway: assigned IPs,
  hostnames, MACs, and lease expiry timestamps.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Lease fields

    * `mac`, `ip`, `hostname`
    * `network_id`, `network_name`
    * `lease_time`, `expires_at`
    * `is_static` — boolean (true for reserved leases)
  """

  use UnifiApi.Resource, api: :network_v1

  @doc """
  Returns the active DHCP lease table.

  ## Options

  Validated with `Keyword.validate!/2` — an unknown key raises
  `ArgumentError` rather than being silently dropped.

    * `:params` — query params forwarded verbatim to the endpoint.
    * `:raw` — when `true`, return the raw response body binary (skips
      JSON decoding and the v1 envelope unwrap). Useful on a large lease
      table when the caller streams or re-serialises the JSON.

  Deliberately **no `:limit` / `:offset`**: this is a v2 snapshot endpoint
  that answers with the gateway's current lease table in one response, and
  the v1 `_start` / `_limit` params do not apply to `/v2/api/...` handlers.
  Advertising a paging option the handler ignores would be worse than
  having none. Use `:params` for anything your controller build does
  accept.

  ## Pagination — one response, no `stream/3`

  There is no cursor, no total count, and **no `stream/3`** for this
  endpoint. If your controller caps the response, the v2 paging convention
  is `pageSize` / `pageNumber` (the same pair `UnifiApi.Network.SystemLog`
  and `UnifiApi.Network.ClientsHistory` page on), reachable through
  `:params`; a page shorter than `pageSize` is the last one. Compare the
  lease count against the expected size of your DHCP scope if you need to
  be certain the table is complete.

  ## Examples

      {:ok, leases} = UnifiApi.Network.ActiveLeases.list(authed, "default")

      # Static reservations only
      static = Enum.filter(leases, & &1["is_static"])

      # Escape hatch: explicit v2 paging
      {:ok, page_1} = UnifiApi.Network.ActiveLeases.list(authed, "default",
        params: [pageSize: 500, pageNumber: 1])
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, [:params, :raw])

    Client.get_v1(
      client,
      "#{prefix(client)}/v2/api/site/#{id!(site_id)}/active-leases",
      opts
    )
  end
end
