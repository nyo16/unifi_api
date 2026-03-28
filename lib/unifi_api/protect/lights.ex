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

  alias UnifiApi.Client

  defp prefix, do: Client.protect_prefix()

  @doc """
  Lists all lights.

  ## Examples

      {:ok, lights} = UnifiApi.Protect.Lights.list(client)

      # Find lights that are currently on
      on_lights = Enum.filter(lights, & &1["isLightOn"])
  """
  @spec list(Req.Request.t()) :: {:ok, term()} | {:error, term()}
  def list(client) do
    Client.get(client, "#{prefix()}/v1/lights")
  end

  @doc """
  Gets a specific light by ID.

  ## Examples

      {:ok, light} = UnifiApi.Protect.Lights.get(client, light_id)
      light["name"]  # => "Garage Flood"
      light["state"] # => "CONNECTED"
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(client, id) do
    Client.get(client, "#{prefix()}/v1/lights/#{id}")
  end

  @doc """
  Updates light settings.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Lights.update(client, light_id, %{
        name: "Garage Flood",
        lightDeviceSettings: %{ledLevel: 4, pirSensitivity: 80}
      })
  """
  @spec update(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def update(client, id, body) do
    Client.patch(client, "#{prefix()}/v1/lights/#{id}", body)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all lights.

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression

  ## Examples

      UnifiApi.Protect.Lights.stream(client)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/lights", opts)
  end
end
