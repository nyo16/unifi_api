defmodule UnifiApi.Network.Events do
  @moduledoc """
  UniFi Network API (v1) — site events.

  Returns the controller's event log: client connect/disconnect, AP
  adopt/disconnect, firmware updates, IPS events bubbled up, etc.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Event fields

  Each event is a map with at least:

    * `_id`, `time` (unix ms), `datetime` (ISO 8601), `site_id`
    * `key` — the event class, e.g. `"EVT_AP_Connected"`,
      `"EVT_WU_Connected"`, `"EVT_LU_Disconnected"`,
      `"EVT_FW_Restarted"`, `"EVT_IPS_IpsAlert"`
    * `subsystem` — `"wlan"`, `"lan"`, `"wan"`, `"vpn"`, `"system"`
    * `msg` — human-readable description

  Wireless events additionally have: `ap`, `ap_name`, `ap_displayName`,
  `radio`, `essid`, `channel`, `bytes`, `duration`.

  Wired events have: `sw`, `sw_name`, `network`, `gw`, `gw_name`.

  Client-related events have: `user`, `hostname`.

  > **Note:** Endpoint shapes are based on community-documented behaviour
  > (see `unpoller/unpoller`). They have not been exercised end-to-end
  > against live hardware in this release — file an issue if a field is
  > missing or shaped differently on your controller.
  """

  alias UnifiApi.Client

  @doc """
  Lists site events.

  ## Options

    * `:within_hours` — return events within the last N hours
      (server-side, sent as `within=N`)
    * `:limit` — max number of events to return (sent as `_limit=N`)
    * `:start` — pagination offset within the result set (sent as
      `_start=N`)

  ## Examples

      # Last 24 hours, up to 1000 events
      {:ok, events} = UnifiApi.Network.Events.list(client, "default",
        within_hours: 24, limit: 1000)

      # Filter to wireless connection events client-side
      events
      |> Enum.filter(&(&1["subsystem"] == "wlan"))
  """
  @spec list(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id, opts \\ []) do
    params =
      []
      |> maybe_param(:within, opts[:within_hours])
      |> maybe_param(:_limit, opts[:limit])
      |> maybe_param(:_start, opts[:start])

    Client.get_v1(client, "#{prefix()}/api/s/#{site_id}/stat/event", params: params)
  end

  defp maybe_param(params, _key, nil), do: params
  defp maybe_param(params, key, value), do: [{key, value} | params]

  defp prefix, do: Client.v1_prefix()
end
