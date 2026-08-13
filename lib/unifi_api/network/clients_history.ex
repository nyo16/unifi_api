defmodule UnifiApi.Network.ClientsHistory do
  @moduledoc """
  UniFi Network API (v2) — client history.

  Returns past client connections — devices that have been seen on the
  network even if they're currently offline. Complements
  `UnifiApi.Network.ClientsLive` (currently-connected) with longer-tail
  history.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Client fields

    * `id`, `mac`, `name`, `hostname`, `oui`
    * `is_wired`, `is_guest`
    * `first_seen`, `last_seen`, `connected_time`
    * `network`, `ap_mac` / `ap_name` for wireless
    * `manufacturer`, `os_name`
  """

  use UnifiApi.Resource, api: :network_v1

  # `stream/3`'s full option set: the module-specific keys plus the
  # `Client.stream_paged/2` pass-through keys. Both lists are forwarded
  # explicitly rather than splatting `opts`, so a module-specific key
  # like `:search` can never leak into `Client`, and
  # `Keyword.validate!/2` turns a typo such as `max_item:` into an
  # `ArgumentError` instead of a silently dropped cap that would page
  # the entire client history.
  #
  # `:limit` is deliberately absent from the pass-through list: this
  # wrapper owns it, sending it as `pageSize` on every request *and*
  # handing it to `stream_paged/2` as its short-page threshold. Adding it
  # here would apply it twice.
  @stream_pass_through [:max_pages, :max_items, :raise_errors]
  @stream_opts [:within_hours, :type, :search, :limit | @stream_pass_through]

  @doc """
  Lists historical clients.

  ## Options

    * `:within_hours` — `withinHours=N`.
    * `:type` — filter by `"WIRED"` / `"WIRELESS"` / `"GUEST"` / `"VPN"`
      (sent as `type=...`).
    * `:search` — string match against name/hostname (`searchString=...`).
    * `:limit` — `pageSize=N`. Default 200 (reduced from 500 in v0.4.0
      to bound per-page memory).
    * `:offset` — `pageNumber=N`.
    * `:raw` — when `true`, return the raw response body binary (skips
      JSON decoding and v1 envelope unwrap).
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    params =
      []
      |> maybe_param(:withinHours, opts[:within_hours])
      |> maybe_param(:type, opts[:type])
      |> maybe_param(:searchString, opts[:search])
      |> maybe_param(:pageSize, opts[:limit])
      |> maybe_param(:pageNumber, opts[:offset])

    Client.get_v1(
      client,
      "#{prefix(client)}/v2/api/site/#{id!(site_id)}/clients/history",
      Keyword.take(opts, [:raw]) ++ [params: params]
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates client history via
  `pageSize` / `pageNumber`.

  ## Error contract

  A mid-stream error does **not** raise by default: the stream halts and
  yields `{:error, %UnifiApi.StreamError{}, last_page}` as its final element,
  so the enumerable is heterogeneous and `Enum.map(stream, & &1["key"])`
  crashes on a transient 500. Match the tail:

      items = Enum.to_list(stream)

      case List.last(items) do
        {:error, error, cursor} -> {:error, error, cursor}
        _ -> {:ok, items}
      end

  Pass `raise_errors: true` to raise `UnifiApi.StreamError` instead.

  ## Options

    * `:within_hours`, `:type`, `:search` — same as `list/3`; sent on
      every page request.
    * `:limit` — page size (default 200), sent as `pageSize`.
    * `:max_pages` — halt after this many successful pages (default:
      unbounded).
    * `:max_items` — halt once this many clients have been yielded; the
      final page is truncated to fit (default: unbounded).
    * `:raise_errors` — when `true`, raise `UnifiApi.StreamError` on a
      mid-stream error instead of yielding `{:error, reason, last_page}`
      as the final element (default: `false`).

  `:max_pages`, `:max_items` and `:raise_errors` are forwarded verbatim
  to `UnifiApi.Client.stream_paged/2` and behave exactly as they do in
  `UnifiApi.Client.stream/3`. Any other key raises `ArgumentError`.

  ## Examples

      # The first 100 wireless clients seen in the last week
      UnifiApi.Network.ClientsHistory.stream(authed, "default",
        within_hours: 168, type: "WIRELESS", max_items: 100)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, @stream_opts)
    page_size = opts[:limit] || 200

    base_params =
      []
      |> maybe_param(:withinHours, opts[:within_hours])
      |> maybe_param(:type, opts[:type])
      |> maybe_param(:searchString, opts[:search])

    path = "#{prefix(client)}/v2/api/site/#{id!(site_id)}/clients/history"

    Client.stream_paged(
      fn page ->
        Client.get_v1(client, path,
          params: base_params ++ [pageSize: page_size, pageNumber: page]
        )
      end,
      [limit: page_size] ++ Keyword.take(opts, @stream_pass_through)
    )
  end
end
