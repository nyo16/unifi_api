defmodule UnifiApi.Network.ClientsLive do
  @moduledoc """
  UniFi Network API (v1) — live wireless client statistics.

  Returns the rich, real-time client data the controller dashboard uses:
  RSSI, signal/noise, CCQ, satisfaction, tx/rx rate and MCS index, retry
  counts, AP attachment, channel/radio info, OS/device fingerprinting.

  This is the endpoint to use for wireless quality dashboards — the
  integration `UnifiApi.Network.Clients.list/3` returns a much thinner
  shape.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Client fields (selected)

  Identity:

    * `_id`, `mac`, `ip`, `hostname`, `name`, `oui`
    * `network`, `network_id`, `vlan`
    * `is_wired`, `is_guest`

  Wireless link quality:

    * `signal` (dBm), `noise` (dBm), `rssi` (dB), `ccq`
    * `satisfaction` (0..100)
    * `tx_rate`, `rx_rate` (Kbps)
    * `tx_mcs`, `rx_mcs`
    * `radio_proto` — `"ng"`, `"na"`, `"ac"`, `"ax"`
    * `channel`, `essid`, `bssid`

  AP attachment:

    * `ap_mac`, `ap_name`, `ap_displayName`

  Counters / timing:

    * `tx_bytes`, `rx_bytes`, `tx_packets`, `rx_packets`, `tx_retries`
    * `uptime`, `idletime`, `assoc_time`, `last_seen`, `roam_count`

  Device fingerprinting:

    * `os_class`, `os_name`, `dev_family`, `dev_id`, `dev_vendor`,
      `dev_cat`

  > **Note:** Field set is based on community documentation. The
  > actual response varies by AP firmware and client OS. Treat any
  > field as optional.
  """

  use UnifiApi.Resource, api: :network_v1

  @doc """
  Lists currently-connected clients with full statistics.

  ## Examples

      {:ok, clients} = UnifiApi.Network.ClientsLive.list(client, "default")

      # Worst-RSSI clients
      clients
      |> Enum.reject(& &1["is_wired"])
      |> Enum.sort_by(& &1["signal"])
      |> Enum.take(10)
  """
  @spec list(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id) do
    Client.get_v1(client, "#{prefix(client)}/api/s/#{id!(site_id)}/stat/sta")
  end

  @doc """
  Lists every client the controller has ever seen, including offline ones.

  Returns the same shape as `list/2` plus a `last_seen` timestamp and
  `first_seen`. Useful for historical inventory and "where did this
  device go?" investigations.

  ## Options

    * `:within_hours` — only include clients seen within the last N hours.
  """
  @spec list_all(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list_all(client, site_id, opts \\ []) do
    params =
      case opts[:within_hours] do
        nil -> []
        n -> [{:within, n}]
      end

    Client.get_v1(client, "#{prefix(client)}/api/s/#{id!(site_id)}/stat/alluser", params: params)
  end
end
