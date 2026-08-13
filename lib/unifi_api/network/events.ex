defmodule UnifiApi.Network.Events do
  @moduledoc """
  UniFi Network API (v1) — site events.

  Returns the controller's event log: client connect/disconnect, AP
  adopt/disconnect, firmware updates, IPS events bubbled up, etc.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Event fields

  Each event is a map with at least:

    * `_id`, `time` (unix ms), `datetime` (ISO 8601), `site_id`
    * `key` — the event class, e.g. `"EVT_AP_Connected"`,
      `"EVT_WU_Connected"`, `"EVT_LU_Disconnected"`,
      `"EVT_FW_Restarted"`, `"EVT_IPS_IpsAlert"`
    * `subsystem` — `"wlan"`, `"lan"`, `"wan"`, `"vpn"`, `"system"`
    * `msg` — human-readable description

  Wireless events additionally have: `ap`, `ap_name`, `ap_displayName`,
  `radio`, `essid`, `channel`, `bytes`, `duration`.

  Wired events have: `sw`, `sw_name`, `network`, `gw`, `gw_name`.

  Client-related events have: `user`, `hostname`.

  > **Note:** Endpoint shapes are based on community-documented behaviour
  > (see `unpoller/unpoller`). They have not been exercised end-to-end
  > against live hardware in this release — file an issue if a field is
  > missing or shaped differently on your controller.
  """

  use UnifiApi.Resource, api: :network_v1

  # `stream/3`'s full option set: the module-specific keys plus the
  # `Client.stream_v1/3` pass-through keys. Both lists are forwarded
  # explicitly rather than splatting `opts`, so a module-specific key
  # like `:within_hours` can never leak into `Client`, and
  # `Keyword.validate!/2` turns a typo such as `max_item:` into an
  # `ArgumentError` instead of a silently dropped cap that would page
  # the entire event log.
  @stream_pass_through [:max_pages, :max_items, :raise_errors]
  @stream_opts [:within_hours, :limit | @stream_pass_through]

  @doc """
  Lists site events.

  ## Options

    * `:within_hours` — return events within the last N hours
      (server-side, sent as `within=N`)
    * `:limit` — max number of events to return (sent as `_limit=N`)
    * `:start` — pagination offset within the result set (sent as
      `_start=N`)
    * `:raw` — when `true`, return the raw response body binary
      (skips JSON decoding and v1 envelope unwrap). Useful for very
      long event windows where the decoded `meta`/`data` envelope
      would be memory-heavy.

  ## Examples

      # Last 24 hours, up to 1000 events
      {:ok, events} = UnifiApi.Network.Events.list(client, "default",
        within_hours: 24, limit: 1000)

      # Filter to wireless connection events client-side
      events
      |> Enum.filter(&(&1["subsystem"] == "wlan"))
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    params =
      []
      |> maybe_param(:within, opts[:within_hours])
      |> maybe_param(:_limit, opts[:limit])
      |> maybe_param(:_start, opts[:start])

    Client.get_v1(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/stat/event",
      Keyword.take(opts, [:raw]) ++ [params: params]
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates events via `_start` / `_limit`.

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

    * `:within_hours` — passed through to every page request as
      `within=N`.
    * `:limit` — page size (default 200).
    * `:max_pages` — halt after this many successful pages (default:
      unbounded).
    * `:max_items` — halt once this many events have been yielded; the
      final page is truncated to fit (default: unbounded).
    * `:raise_errors` — when `true`, raise `UnifiApi.StreamError` on a
      mid-stream error instead of yielding `{:error, reason, last_start}`
      as the final element (default: `false`).

  `:max_pages`, `:max_items` and `:raise_errors` are forwarded verbatim
  to `UnifiApi.Client.stream_v1/3` and behave exactly as they do in
  `UnifiApi.Client.stream/3`. Any other key raises `ArgumentError`.

  ## Examples

      # Stream every event in the last 24 hours
      UnifiApi.Network.Events.stream(authed, "default", within_hours: 24)
      |> Enum.to_list()

      # Bound the work server-side: at most 100 events, at most 2 requests
      UnifiApi.Network.Events.stream(authed, "default", max_items: 100, max_pages: 2)
      |> Enum.to_list()

      # Stop early — only fetches one page
      UnifiApi.Network.Events.stream(authed, "default")
      |> Enum.take(50)
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, @stream_opts)
    base_params = maybe_param([], :within, opts[:within_hours])

    Client.stream_v1(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/stat/event",
      [limit: opts[:limit] || 200, params: base_params] ++
        Keyword.take(opts, @stream_pass_through)
    )
  end
end
