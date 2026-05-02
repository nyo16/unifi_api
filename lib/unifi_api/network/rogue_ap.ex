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

  alias UnifiApi.Client

  @doc """
  Lists active (currently visible) rogue / neighbouring APs.
  """
  @spec list(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id) do
    Client.get_v1(client, "#{prefix()}/api/s/#{site_id}/stat/rogueap")
  end

  @doc """
  Lists APs the operator has explicitly acknowledged / known-listed.
  """
  @spec list_known(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def list_known(client, site_id) do
    Client.get_v1(client, "#{prefix()}/api/s/#{site_id}/rest/rogueknown")
  end

  defp prefix, do: Client.v1_prefix()
end
