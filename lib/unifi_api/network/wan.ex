defmodule UnifiApi.Network.WAN do
  @moduledoc """
  UniFi Network API (v2) — WAN / ISP health.

  Reports gateway WAN status, ISP up/down state, load-balancing config,
  and SLA monitoring data.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Endpoints exposed

    * `enriched_config/2` — full WAN configuration with derived state.
    * `isp_status/3` — ISP reachability and latency for one WAN id.
    * `load_balancing/2` — multi-WAN load-balance configuration / status.
    * `slas/2` — Internet SLA monitoring history.
  """

  alias UnifiApi.Client

  @doc """
  Returns the enriched WAN configuration: per-WAN type, identifiers,
  and derived state.
  """
  @spec enriched_config(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def enriched_config(client, site_id) do
    Client.get_v1(client, "#{prefix()}/v2/api/site/#{site_id}/wan/enriched-configuration")
  end

  @doc """
  Returns ISP reachability and latency status for a specific WAN.
  """
  @spec isp_status(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, term()}
  def isp_status(client, site_id, wan_id) do
    Client.get_v1(client, "#{prefix()}/v2/api/site/#{site_id}/wan/#{wan_id}/isp-status")
  end

  @doc """
  Returns the multi-WAN load-balancing configuration and current
  per-WAN weights.
  """
  @spec load_balancing(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def load_balancing(client, site_id) do
    Client.get_v1(client, "#{prefix()}/v2/api/site/#{site_id}/wan/load-balancing")
  end

  @doc """
  Returns SLA monitoring data for the site's WAN connections.
  """
  @spec slas(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def slas(client, site_id) do
    Client.get_v1(client, "#{prefix()}/v2/api/site/#{site_id}/wan-slas")
  end

  defp prefix, do: Client.v1_prefix()
end
