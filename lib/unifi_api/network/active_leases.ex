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

  alias UnifiApi.Client

  @doc """
  Returns the active DHCP lease table.
  """
  @spec list(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id) do
    Client.get_v1(client, "#{prefix()}/v2/api/site/#{site_id}/active-leases")
  end

  defp prefix, do: Client.v1_prefix()
end
