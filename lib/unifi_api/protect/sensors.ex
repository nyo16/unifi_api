defmodule UnifiApi.Protect.Sensors do
  @moduledoc """
  UniFi Protect API — sensor management.

  Lists Protect sensor devices (door/window, motion, leak, etc.).

  ## Response fields

    * `id`, `modelKey`, `name`, `mac`
    * `state` — `"CONNECTED"`, `"CONNECTING"`, or `"DISCONNECTED"`
    * `mountType`, `batteryStatus`, `stats`
    * `lightSettings`, `humiditySettings`, `temperatureSettings`
    * `isOpened`, `isMotionDetected`
    * `alarmSettings`, `leakSettings`
  """

  use UnifiApi.Resource, api: :protect

  @doc """
  Lists sensors.

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
  every sensor. A low-battery or open-door sweep built on `list/2` scans
  one page and silently misses the rest.

  ## Examples

      {:ok, sensors} = UnifiApi.Protect.Sensors.list(client)

      # Find open doors/windows
      open = Enum.filter(sensors, & &1["isOpened"])

      # Check battery levels across every sensor, not just the first page
      low_battery =
        UnifiApi.Protect.Sensors.stream(client)
        |> Enum.filter(fn s -> s["batteryStatus"]["percentage"] < 20 end)
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, opts \\ []) do
    opts = Keyword.validate!(opts, [:limit, :offset, :filter, :params, :raw])

    Client.get(client, "#{prefix(client)}/v1/sensors", opts)
  end

  @doc """
  Gets a specific sensor by ID.

  ## Examples

      {:ok, sensor} = UnifiApi.Protect.Sensors.get(client, sensor_id)
      sensor["name"]  # => "Back Door"
      sensor["state"] # => "CONNECTED"
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get(client, id) do
    Client.get(client, "#{prefix(client)}/v1/sensors/#{id!(id)}")
  end

  @doc """
  Updates sensor settings.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Sensors.update(client, sensor_id, %{
        name: "Back Door Sensor",
        mountType: "door"
      })
  """
  @spec update(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def update(client, id, body) do
    Client.patch(client, "#{prefix(client)}/v1/sensors/#{id!(id)}", body)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all sensors.

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

      UnifiApi.Protect.Sensors.stream(client)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Client.stream(client, "#{prefix(client)}/v1/sensors", opts)
  end
end
