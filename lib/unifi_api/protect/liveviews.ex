defmodule UnifiApi.Protect.Liveviews do
  @moduledoc """
  UniFi Protect API — liveview management.

  Lists configured liveview layouts for Protect viewports.

  ## Response fields

    * `id`, `modelKey`, `name`
    * `isDefault`, `isGlobal`, `owner`
    * `layout` — grid layout (1-26)
    * `slots` — list of `%{cameras, cycleMode, cycleInterval}`
  """

  use UnifiApi.Resource, api: :protect

  @doc """
  Lists liveviews.

  ## Options

  Validated with `Keyword.validate!/2` — an unknown key raises
  `ArgumentError` rather than being silently dropped. Forwarded to
  `UnifiApi.Client.get/3`:

    * `:limit` — page size (controller default: 25, max: 200)
    * `:offset` — page offset (default: 0)
    * `:filter` — UniFi filter expression
    * `:params` — extra query params, merged verbatim
    * `:raw` — when `true`, skip JSON decoding and return the raw
      response body binary

  ## Pagination — first page only

  The endpoint is paginated and the response carries no total count and no
  cursor, so a full page is indistinguishable from a truncated one.
  `list/2` returns **the first page only** — use `stream/2` to enumerate
  every liveview. Searching for the default liveview via `list/2` can come
  up empty simply because it sits on a later page.

  ## Examples

      {:ok, liveviews} = UnifiApi.Protect.Liveviews.list(client)

      # Find the default liveview across every page
      default =
        UnifiApi.Protect.Liveviews.stream(client)
        |> Enum.find(& &1["isDefault"])
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, opts \\ []) do
    opts = Keyword.validate!(opts, [:limit, :offset, :filter, :params, :raw])

    Client.get(client, "#{prefix(client)}/v1/liveviews", opts)
  end

  @doc """
  Gets a specific liveview by ID.

  ## Examples

      {:ok, liveview} = UnifiApi.Protect.Liveviews.get(client, liveview_id)
      liveview["name"]   # => "All Cameras"
      liveview["layout"] # => 4
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get(client, id) do
    Client.get(client, "#{prefix(client)}/v1/liveviews/#{id!(id)}")
  end

  @doc """
  Returns a lazy stream that auto-paginates through all liveviews.

  ## Error contract

  A mid-stream error does **not** raise by default: the stream halts and
  yields `{:error, %UnifiApi.StreamError{}, last_offset}` as its final
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

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression
    * `:max_pages` — halt after this many successful pages (default: unbounded).
    * `:max_items` — halt once this many items have been yielded (default: unbounded).
    * `:raise_errors` — raise `UnifiApi.StreamError` on error instead of
      yielding the error tuple (default: `false`).

  ## Examples

      UnifiApi.Protect.Liveviews.stream(client)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Client.stream(client, "#{prefix(client)}/v1/liveviews", opts)
  end
end
