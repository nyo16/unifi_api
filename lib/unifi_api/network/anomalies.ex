defmodule UnifiApi.Network.Anomalies do
  @moduledoc """
  UniFi Network API (v1) — anomalies.

  Returns the controller's anomaly history: client connect failures,
  poor signal events, channel saturation, and similar diagnostic noise
  the controller flags automatically.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Anomaly fields

    * `_id`, `time`, `datetime`, `site_id`
    * `anomaly` — the class label, e.g. `"poor_signal"`,
      `"too_many_clients"`, `"high_retries"`
    * `mac`, `ap`, `subsystem`
    * `count` — occurrences in the reporting window

  > **Note:** Field set is community-documented; treat any field as
  > optional.
  """

  use UnifiApi.Resource, api: :network_v1

  @doc """
  Lists site anomalies.

  ## Options

    * `:within_hours` — return anomalies seen within the last N hours
      (sent as `within=N`).
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    params =
      case opts[:within_hours] do
        nil -> []
        n -> [{:within, n}]
      end

    Client.get_v1(client, "#{prefix(client)}/api/s/#{id!(site_id)}/stat/anomalies",
      params: params
    )
  end
end
