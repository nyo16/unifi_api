defmodule UnifiApi.Protect.Events do
  @moduledoc """
  UniFi Protect API — event log.

  Returns motion, ring, smartDetect, and recording events emitted by
  Protect cameras and other devices. Use this for security automation
  ("when the front door rings, do X") or for ad-hoc forensics ("what
  motion was detected last Tuesday around midnight?").

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Event fields

    * `id`, `type` — `"motion"`, `"ring"`, `"smartDetectZone"`,
      `"smartAudioDetect"`, `"recording"`, `"package"`
    * `start`, `end` — unix milliseconds
    * `score` — confidence (0..100) for smart detections
    * `camera`, `cameraId` — source device
    * `smartDetectTypes` — list of `"person"`, `"vehicle"`, `"animal"`,
      `"package"`, `"licensePlate"` for smart events
    * `thumbnail`, `heatmap` — opaque IDs to fetch via
      `thumbnail/3` (binary JPEG)
  """

  alias UnifiApi.Client

  @prefix "/proxy/protect"

  @doc """
  Lists events.

  ## Options

    * `:start` — window start, unix milliseconds.
    * `:end` — window end, unix milliseconds.
    * `:types` — filter to specific event types, list of strings.
    * `:cameras` — filter to specific camera ids, list of strings.
    * `:limit` — server-side cap.

  ## Examples

      # Last hour, motion only
      hour_ago = (System.os_time(:millisecond) - 60 * 60 * 1000)

      {:ok, events} = UnifiApi.Protect.Events.list(client,
        start: hour_ago, types: ["motion", "smartDetectZone"], limit: 100)
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(client, opts \\ []) do
    params =
      []
      |> maybe_param(:start, opts[:start])
      |> maybe_param(:end, opts[:end])
      |> maybe_param(:limit, opts[:limit])
      |> maybe_csv(:types, opts[:types])
      |> maybe_csv(:cameras, opts[:cameras])

    Client.get(client, "#{@prefix}/api/events", params: params)
  end

  @doc """
  Returns a single event by id.
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(client, event_id) do
    Client.get(client, "#{@prefix}/api/events/#{event_id}")
  end

  @doc """
  Returns the event thumbnail as a JPEG binary.

  ## Examples

      {:ok, jpeg} = UnifiApi.Protect.Events.thumbnail(client, event_id)
      File.write!("event.jpg", jpeg)
  """
  @spec thumbnail(Req.Request.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def thumbnail(client, event_id, opts \\ []) do
    params =
      []
      |> maybe_param(:w, opts[:width])
      |> maybe_param(:h, opts[:height])

    Client.get_raw(client, "#{@prefix}/api/events/#{event_id}/thumbnail", params: params)
  end

  @doc """
  Returns Protect's system event log (firmware updates, NVR events,
  device adoption, etc. — distinct from camera events).
  """
  @spec system_logs(Req.Request.t()) :: {:ok, term()} | {:error, term()}
  def system_logs(client) do
    Client.get(client, "#{@prefix}/api/events/system-logs")
  end

  defp maybe_param(params, _key, nil), do: params
  defp maybe_param(params, key, value), do: [{key, value} | params]

  defp maybe_csv(params, _key, nil), do: params
  defp maybe_csv(params, _key, []), do: params
  defp maybe_csv(params, key, list), do: [{key, Enum.join(list, ",")} | params]
end
