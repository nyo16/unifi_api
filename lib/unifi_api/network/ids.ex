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

  use UnifiApi.Resource, api: :network_v1

  # `stream/3`'s full option set: the module-specific keys plus the
  # `Client.stream_v1/3` pass-through keys. Both lists are forwarded
  # explicitly rather than splatting `opts`, so a module-specific key
  # like `:within_hours` can never leak into `Client`, and
  # `Keyword.validate!/2` turns a typo such as `max_item:` into an
  # `ArgumentError` instead of a silently dropped cap that would page
  # every detection the IPS engine ever logged.
  @stream_pass_through [:max_pages, :max_items, :raise_errors]
  @stream_opts [:within_hours, :limit | @stream_pass_through]

  @doc """
  Lists IDS / IPS events.

  ## Options

    * `:within_hours` — `within=N`.
    * `:limit` — `_limit=N`.
    * `:start` — `_start=N`.
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    params =
      []
      |> maybe_param(:within, opts[:within_hours])
      |> maybe_param(:_limit, opts[:limit])
      |> maybe_param(:_start, opts[:start])

    Client.get_v1(client, "#{prefix(client)}/api/s/#{id!(site_id)}/stat/ips/event",
      params: params
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates IDS / IPS events via
  `_start` / `_limit`.

  ## Error contract

  A mid-stream error does **not** raise by default: the stream halts and
  yields `{:error, %UnifiApi.StreamError{}, last_start}` as its final element,
  so the enumerable is heterogeneous and `Enum.map(stream, & &1["key"])`
  crashes on a transient 500. Match the tail:

      items = Enum.to_list(stream)

      case List.last(items) do
        {:error, error, cursor} -> {:error, error, cursor}
        _ -> {:ok, items}
      end

  Pass `raise_errors: true` to raise `UnifiApi.StreamError` instead.

  ## Options

    * `:within_hours` — passed through to every page as `within=N`.
    * `:limit` — page size (default 500).
    * `:max_pages` — halt after this many successful pages (default:
      unbounded).
    * `:max_items` — halt once this many detections have been yielded;
      the final page is truncated to fit (default: unbounded).
    * `:raise_errors` — when `true`, raise `UnifiApi.StreamError` on a
      mid-stream error instead of yielding `{:error, reason, last_start}`
      as the final element (default: `false`).

  `:max_pages`, `:max_items` and `:raise_errors` are forwarded verbatim
  to `UnifiApi.Client.stream_v1/3` and behave exactly as they do in
  `UnifiApi.Client.stream/3`. Any other key raises `ArgumentError`.

  ## Examples

      # The 100 most recent detections in the last 12 hours
      UnifiApi.Network.IDS.stream(authed, "default", within_hours: 12, max_items: 100)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, @stream_opts)
    base_params = maybe_param([], :within, opts[:within_hours])

    Client.stream_v1(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/stat/ips/event",
      [limit: opts[:limit] || 500, params: base_params] ++
        Keyword.take(opts, @stream_pass_through)
    )
  end
end
