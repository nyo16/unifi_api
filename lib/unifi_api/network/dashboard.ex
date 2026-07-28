defmodule UnifiApi.Network.Dashboard do
  @moduledoc """
  UniFi Network API (v2) — aggregated dashboard.

  Returns the pre-aggregated payload that powers the controller's
  dashboard view: client/device counts, traffic totals, top apps, top
  clients, and time-series for the configured history window. A single
  network call instead of stitching together
  `UnifiApi.Network.Clients`, `Devices`, `Traffic`, etc.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Response shape

  Map with at least:

    * `clients` — current totals broken down by type
    * `devices` — current totals broken down by type and state
    * `traffic` — totals + time series for the window
    * `topClients`, `topApps`
    * `wanStatus` — per-WAN reachability
  """

  alias UnifiApi.Client

  @doc """
  Returns the aggregated dashboard payload.

  ## Options

    * `:history_seconds` — window length, default `3600` (last hour).
      Common values: `3600` (1h), `86400` (24h), `604800` (7d).

  ## Examples

      {:ok, dashboard} = UnifiApi.Network.Dashboard.get(client, "default")

      # Last week
      {:ok, weekly} = UnifiApi.Network.Dashboard.get(client, "default",
        history_seconds: 604_800)
  """
  @spec get(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get(client, site_id, opts \\ []) do
    seconds = Keyword.get(opts, :history_seconds, 3600)

    Client.get_v1(client, "#{prefix()}/v2/api/site/#{site_id}/aggregated-dashboard",
      params: [historySeconds: seconds]
    )
  end

  defp prefix, do: Client.v1_prefix()
end
