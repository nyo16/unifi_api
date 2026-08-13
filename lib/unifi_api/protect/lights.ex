defmodule UnifiApi.Protect.Lights do
  @moduledoc """
  UniFi Protect API — light management.

  Lists Protect smart floodlight devices.

  ## Response fields

    * `id`, `modelKey`, `name`, `mac`
    * `state` — `"CONNECTED"`, `"CONNECTING"`, or `"DISCONNECTED"`
    * `isDark`, `isLightOn`, `lastMotion`
    * `lightModeSettings` — `%{mode, enableAt}`
    * `lightDeviceSettings` — `%{isIndicatorEnabled, pirDuration, pirSensitivity, ledLevel}`
    * `camera` — associated camera ID
  """

  use UnifiApi.Resource, api: :protect

  @doc """
  Lists lights.

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
  every light. `Enum.filter/2` over `list/2` therefore filters one page,
  not the whole installation.

  ## Examples

      {:ok, lights} = UnifiApi.Protect.Lights.list(client)

      # Find lights that are currently on
      on_lights = Enum.filter(lights, & &1["isLightOn"])

      # Second page of 50
      {:ok, lights} = UnifiApi.Protect.Lights.list(client, limit: 50, offset: 50)
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, opts \\ []) do
    opts = Keyword.validate!(opts, [:limit, :offset, :filter, :params, :raw])

    Client.get(client, "#{prefix(client)}/v1/lights", opts)
  end

  @doc """
  Gets a specific light by ID.

  ## Examples

      {:ok, light} = UnifiApi.Protect.Lights.get(client, light_id)
      light["name"]  # => "Garage Flood"
      light["state"] # => "CONNECTED"
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get(client, id) do
    Client.get(client, "#{prefix(client)}/v1/lights/#{id!(id)}")
  end

  @doc """
  Updates light settings.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Lights.update(client, light_id, %{
        name: "Garage Flood",
        lightDeviceSettings: %{ledLevel: 4, pirSensitivity: 80}
      })
  """
  @spec update(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def update(client, id, body) do
    Client.patch(client, "#{prefix(client)}/v1/lights/#{id!(id)}", body)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all lights.

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

      UnifiApi.Protect.Lights.stream(client)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Client.stream(client, "#{prefix(client)}/v1/lights", opts)
  end
end
