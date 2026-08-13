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

  use UnifiApi.Resource, api: :network_v1

  # `stream/3`'s full option set: the module-specific keys plus the
  # `Client.stream_v1/3` pass-through keys. Both lists are forwarded
  # explicitly rather than splatting `opts`, so a module-specific key
  # like `:archived` can never leak into `Client`, and
  # `Keyword.validate!/2` turns a typo such as `max_item:` into an
  # `ArgumentError` instead of a silently dropped cap that would page
  # the entire alarm log.
  @stream_pass_through [:max_pages, :max_items, :raise_errors]
  @stream_opts [:archived, :limit | @stream_pass_through]

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
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    params =
      []
      |> maybe_param(:archived, opts[:archived])
      |> maybe_param(:_limit, opts[:limit])
      |> maybe_param(:_start, opts[:start])

    Client.get_v1(client, "#{prefix(client)}/api/s/#{id!(site_id)}/list/alarm", params: params)
  end

  @doc """
  Marks an alarm as archived.

  ## Examples

      {:ok, _} = UnifiApi.Network.Alarms.archive(client, "default", alarm_id)
  """
  @spec archive(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def archive(client, site_id, alarm_id) do
    Client.post(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/cmd/evtmgr",
      %{cmd: "archive-alarm", _id: alarm_id}
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates alarms via `_start` / `_limit`.

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

    * `:archived` — `true` for archived only, `false` for active only.
    * `:limit` — page size (default 500).
    * `:max_pages` — halt after this many successful pages (default:
      unbounded).
    * `:max_items` — halt once this many alarms have been yielded; the
      final page is truncated to fit (default: unbounded).
    * `:raise_errors` — when `true`, raise `UnifiApi.StreamError` on a
      mid-stream error instead of yielding `{:error, reason, last_start}`
      as the final element (default: `false`).

  `:max_pages`, `:max_items` and `:raise_errors` are forwarded verbatim
  to `UnifiApi.Client.stream_v1/3` and behave exactly as they do in
  `UnifiApi.Client.stream/3`. Any other key raises `ArgumentError`.

  ## Examples

      # At most 50 active alarms, however many pages that takes
      UnifiApi.Network.Alarms.stream(authed, "default", archived: false, max_items: 50)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, @stream_opts)
    base_params = maybe_param([], :archived, opts[:archived])

    Client.stream_v1(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/list/alarm",
      [limit: opts[:limit] || 500, params: base_params] ++
        Keyword.take(opts, @stream_pass_through)
    )
  end
end
