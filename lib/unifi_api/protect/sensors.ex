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

  alias UnifiApi.Client

  defp prefix, do: Client.protect_prefix()

  @doc """
  Lists all sensors.

  ## Examples

      {:ok, sensors} = UnifiApi.Protect.Sensors.list(client)

      # Find open doors/windows
      open = Enum.filter(sensors, & &1["isOpened"])

      # Check battery levels
      low_battery = Enum.filter(sensors, fn s ->
        s["batteryStatus"]["percentage"] < 20
      end)
  """
  @spec list(Req.Request.t()) :: {:ok, term()} | {:error, term()}
  def list(client) do
    Client.get(client, "#{prefix()}/v1/sensors")
  end

  @doc """
  Gets a specific sensor by ID.

  ## Examples

      {:ok, sensor} = UnifiApi.Protect.Sensors.get(client, sensor_id)
      sensor["name"]  # => "Back Door"
      sensor["state"] # => "CONNECTED"
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(client, id) do
    Client.get(client, "#{prefix()}/v1/sensors/#{id}")
  end

  @doc """
  Updates sensor settings.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Sensors.update(client, sensor_id, %{
        name: "Back Door Sensor",
        mountType: "door"
      })
  """
  @spec update(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def update(client, id, body) do
    Client.patch(client, "#{prefix()}/v1/sensors/#{id}", body)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all sensors.

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression

  ## Examples

      UnifiApi.Protect.Sensors.stream(client)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sensors", opts)
  end
end
