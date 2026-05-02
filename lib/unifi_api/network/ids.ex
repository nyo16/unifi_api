defmodule UnifiApi.Network.IDS do
  @moduledoc """
  UniFi Network API (v1) — IDS / IPS detections.

  Returns events flagged by the gateway's intrusion detection / prevention
  engine: signature matches, blocked outbound, suspect inbound, etc.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Detection fields

    * `_id`, `time`, `datetime`, `site_id`
    * `key` — `"EVT_IPS_IpsAlert"`, `"EVT_IPS_IpsBlocked"`, ...
    * `subsystem` — `"ips"`
    * `app_proto` — application-layer protocol detected
    * `catname` — Suricata category, e.g. `"Misc Attack"`
    * `signature` — Suricata signature text
    * `src_ip`, `dest_ip`, `src_port`, `dst_port`, `proto`
    * `usgip` — gateway IP that observed the event
    * `inner_alert_action` — `"allowed"`, `"blocked"`
    * `host`, `srcMAC`, `dstMAC`

  > **Note:** Shape mirrors the legacy controller console; field
  > availability depends on which IPS engine is active and the firmware
  > revision.
  """

  alias UnifiApi.Client

  @doc """
  Lists IDS / IPS events.

  ## Options

    * `:within_hours` — `within=N`.
    * `:limit` — `_limit=N`.
    * `:start` — `_start=N`.
  """
  @spec list(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id, opts \\ []) do
    params =
      []
      |> maybe_param(:within, opts[:within_hours])
      |> maybe_param(:_limit, opts[:limit])
      |> maybe_param(:_start, opts[:start])

    Client.get_v1(client, "#{prefix()}/api/s/#{site_id}/stat/ips/event", params: params)
  end

  @doc """
  Returns a lazy stream that auto-paginates IDS / IPS events via
  `_start` / `_limit`.

  ## Options

    * `:within_hours` — passed through to every page as `within=N`.
    * `:limit` — page size (default 500).
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    base_params = maybe_param([], :within, opts[:within_hours])

    Client.stream_v1(client, "#{prefix()}/api/s/#{site_id}/stat/ips/event",
      limit: opts[:limit] || 500,
      params: base_params
    )
  end

  defp maybe_param(params, _key, nil), do: params
  defp maybe_param(params, key, value), do: [{key, value} | params]

  defp prefix, do: Client.v1_prefix()
end
