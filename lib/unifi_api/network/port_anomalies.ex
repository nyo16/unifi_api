defmodule UnifiApi.Network.PortAnomalies do
  @moduledoc """
  UniFi Network API (v2) — switch port anomalies.

  Reports ports flagged by the controller for unusual behaviour: high
  error rate, half-duplex on a presumed gigabit link, PoE faults,
  flapping, etc.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Anomaly fields

    * `device_id`, `device_name`, `port_idx`
    * `anomaly` — the class label
    * `count` — occurrences in the reporting window
    * `last_seen`
  """

  use UnifiApi.Resource, api: :network_v1

  @doc """
  Lists port anomalies for the site.

  ## Options

  Validated with `Keyword.validate!/2` — an unknown key raises
  `ArgumentError` rather than being silently dropped.

    * `:params` — query params forwarded verbatim to the endpoint.
    * `:raw` — when `true`, return the raw response body binary (skips
      JSON decoding and the v1 envelope unwrap).

  Deliberately **no `:limit` / `:offset`**: this is a v2 report endpoint
  that answers with every port flagged in the current reporting window in
  one response, and the v1 `_start` / `_limit` params do not apply to
  `/v2/api/...` handlers. Advertising a paging option the handler ignores
  would be worse than having none. Use `:params` for anything your
  controller build does accept.

  ## Pagination — one response, no `stream/3`

  There is no cursor, no total count, and **no `stream/3`** for this
  endpoint. If your controller caps the response, the v2 paging convention
  is `pageSize` / `pageNumber` (the same pair `UnifiApi.Network.SystemLog`
  and `UnifiApi.Network.ClientsHistory` page on), reachable through
  `:params`; a page shorter than `pageSize` is the last one.

  ## Examples

      {:ok, anomalies} = UnifiApi.Network.PortAnomalies.list(authed, "default")

      # Group by switch
      Enum.group_by(anomalies, & &1["device_name"])

      # Escape hatch: explicit v2 paging
      {:ok, page_1} = UnifiApi.Network.PortAnomalies.list(authed, "default",
        params: [pageSize: 500, pageNumber: 1])
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, [:params, :raw])

    Client.get_v1(
      client,
      "#{prefix(client)}/v2/api/site/#{id!(site_id)}/ports/port-anomalies",
      opts
    )
  end
end
