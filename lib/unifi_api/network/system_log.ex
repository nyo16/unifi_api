defmodule UnifiApi.Network.SystemLog do
  @moduledoc """
  UniFi Network API (v2) — system log.

  Returns the controller's structured system log: device adoption,
  firmware updates, gateway events, threat-management actions, etc. This
  is more focused than `UnifiApi.Network.Events` — events covers all
  client/AP activity, system log covers controller-level operations.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Common entry fields

    * `id`, `timestamp`, `category`, `level`
    * `key`, `subsystem`
    * `description` — human-readable message
    * `device` — when the log line is device-attributed
  """

  use UnifiApi.Resource, api: :network_v1

  # `stream/3`'s full option set. `:limit` is the only key this wrapper
  # owns; the rest are `Client.stream_paged/2` pass-throughs, forwarded
  # explicitly rather than by splatting `opts` so nothing module-specific
  # can leak into `Client`. `Keyword.validate!/2` turns a typo such as
  # `max_item:` into an `ArgumentError` instead of a silently dropped cap
  # that would page the entire system log.
  #
  # `:limit` is deliberately absent from the pass-through list: it is
  # sent as `pageSize` on every request *and* handed to `stream_paged/2`
  # as its short-page threshold. Adding it here would apply it twice.
  @stream_pass_through [:max_pages, :max_items, :raise_errors]
  @stream_opts [:limit | @stream_pass_through]

  @doc """
  Returns all system log entries within the supported window.

  ## Options

    * `:limit` — server-side cap (`pageSize` query param). Default 200
      (reduced from 500 in v0.4.0 to bound per-page memory).
    * `:start` — bucket start (`pageNumber` query param).
    * `:raw` — when `true`, return the raw response body binary
      (skips JSON decoding) — useful for streaming parsers on very
      large logs.
  """
  @spec list_all(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list_all(client, site_id, opts \\ []) do
    params =
      []
      |> maybe_param(:pageSize, opts[:limit])
      |> maybe_param(:pageNumber, opts[:start])

    Client.get_v1(
      client,
      "#{prefix(client)}/v2/api/site/#{id!(site_id)}/system-log/all",
      Keyword.take(opts, [:raw]) ++ [params: params]
    )
  end

  @doc """
  Returns a lazy stream that auto-paginates the system log via
  `pageSize` / `pageNumber`.

  ## Error contract

  A mid-stream error does **not** raise by default: the stream halts and
  yields `{:error, %UnifiApi.StreamError{}, last_page}` as its final
  element, so the enumerable is heterogeneous. Match the tail:

      case Enum.to_list(stream) do
        items when is_list(items) ->
          case List.last(items) do
            {:error, error, cursor} -> {:error, error, cursor}
            _ -> {:ok, items}
          end
      end

  Pass `raise_errors: true` to raise `UnifiApi.StreamError` instead.

  ## Options

    * `:limit` — page size (default 200, reduced from 500 in v0.4.0 to
      bound per-page memory), sent as `pageSize`.
    * `:max_pages` — halt after this many successful pages (default:
      unbounded).
    * `:max_items` — halt once this many entries have been yielded; the
      final page is truncated to fit (default: unbounded).
    * `:raise_errors` — when `true`, raise `UnifiApi.StreamError` on a
      mid-stream error instead of yielding `{:error, reason, last_page}`
      as the final element (default: `false`).

  `:max_pages`, `:max_items` and `:raise_errors` are forwarded verbatim
  to `UnifiApi.Client.stream_paged/2` and behave exactly as they do in
  `UnifiApi.Client.stream/3`. Any other key raises `ArgumentError`.

  ## Examples

      # The 500 most recent entries, without walking the whole log
      UnifiApi.Network.SystemLog.stream(authed, "default", max_items: 500)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, @stream_opts)
    page_size = opts[:limit] || 200
    path = "#{prefix(client)}/v2/api/site/#{id!(site_id)}/system-log/all"

    Client.stream_paged(
      fn page ->
        Client.get_v1(client, path, params: [pageSize: page_size, pageNumber: page])
      end,
      [limit: page_size] ++ Keyword.take(opts, @stream_pass_through)
    )
  end
end
