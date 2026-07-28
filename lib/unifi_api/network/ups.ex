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

  alias UnifiApi.Client

  @doc """
  Lists connected UPS devices on a site.
  """
  @spec list(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id) do
    Client.get_v1(client, "#{prefix()}/api/s/#{site_id}/stat/ups-devices")
  end

  defp prefix, do: Client.v1_prefix()
end
