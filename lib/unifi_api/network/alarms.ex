defmodule UnifiApi.Network.Alarms do
  @moduledoc """
  UniFi Network API (v1) — alarms.

  Returns active and archived alarms — the entries that show in the
  controller dashboard's "Alerts" pane: gateway down, AP disconnected,
  IDS detection, threshold crossings, etc.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Alarm fields

    * `_id`, `key`, `time`, `datetime`, `site_id`
    * `archived` — boolean
    * `msg` — human-readable description
    * `subsystem` — `"wlan"`, `"lan"`, `"wan"`, `"vpn"`, `"system"`,
      `"ips"`, `"alarm"`
    * `severity` — `"info"`, `"warn"`, `"critical"`
    * For IPS alarms: `app_proto`, `catname`, `dest_ip`, `src_ip`,
      `proto`, `signature`, `usgip` (gateway IP), `inner_alert_action`

  > **Note:** Like `Events`, the field set comes from community/unpoller
  > documentation rather than first-party schema. File an issue if your
  > controller returns extra or differently-shaped fields.
  """

  alias UnifiApi.Client

  @doc """
  Lists alarms for a site.

  ## Options

    * `:archived` — `true` returns only archived alarms; `false` returns
      only active ones; `nil` (default) returns both.
    * `:limit` — `_limit=N` server-side cap.
    * `:start` — `_start=N` pagination offset.

  ## Examples

      # All active alarms
      {:ok, alarms} = UnifiApi.Network.Alarms.list(client, "default", archived: false)

      # Just IPS detections
      {:ok, alarms} = UnifiApi.Network.Alarms.list(client, "default")
      Enum.filter(alarms, &(&1["subsystem"] == "ips"))
  """
  @spec list(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id, opts \\ []) do
    params =
      []
      |> maybe_param(:archived, opts[:archived])
      |> maybe_param(:_limit, opts[:limit])
      |> maybe_param(:_start, opts[:start])

    Client.get_v1(client, "#{prefix()}/api/s/#{site_id}/list/alarm", params: params)
  end

  @doc """
  Marks an alarm as archived.

  ## Examples

      {:ok, _} = UnifiApi.Network.Alarms.archive(client, "default", alarm_id)
  """
  @spec archive(Req.Request.t(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def archive(client, site_id, alarm_id) do
    Client.post(
      client,
      "#{prefix()}/api/s/#{site_id}/cmd/evtmgr",
      %{cmd: "archive-alarm", _id: alarm_id}
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates alarms via `_start` / `_limit`.

  ## Options

    * `:archived` — `true` for archived only, `false` for active only.
    * `:limit` — page size (default 500).
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    base_params = maybe_param([], :archived, opts[:archived])

    Client.stream_v1(client, "#{prefix()}/api/s/#{site_id}/list/alarm",
      limit: opts[:limit] || 500,
      params: base_params
    )
  end

  defp maybe_param(params, _key, nil), do: params
  defp maybe_param(params, key, value), do: [{key, value} | params]

  defp prefix, do: Client.v1_prefix()
end
