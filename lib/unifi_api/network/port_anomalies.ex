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

  alias UnifiApi.Client

  @doc """
  Lists port anomalies for the site.
  """
  @spec list(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id) do
    Client.get_v1(client, "#{prefix()}/v2/api/site/#{site_id}/ports/port-anomalies")
  end

  defp prefix, do: Client.v1_prefix()
end
