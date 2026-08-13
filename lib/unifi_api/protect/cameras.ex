defmodule UnifiApi.Protect.Cameras do
  @moduledoc """
  UniFi Protect API — camera management.

  List, view, update cameras, capture snapshots, and control PTZ.

  ## Camera fields

    * `id`, `modelKey`, `name`, `mac`
    * `state` — `"CONNECTED"`, `"CONNECTING"`, or `"DISCONNECTED"`
    * `isMicEnabled`, `micVolume`
    * `osdSettings`, `ledSettings`, `lcdMessage`
    * `activePatrolSlot`, `videoMode`, `hdrType`
    * `featureFlags`, `smartDetectSettings`

  ## Updatable fields

    * `name`, `osdSettings`, `ledSettings`, `lcdMessage`
    * `micVolume`, `videoMode`, `hdrType`, `smartDetectSettings`
  """

  use UnifiApi.Resource, api: :protect

  @doc """
  Lists all cameras.

  ## Options

    * `:raw` — when `true`, return the raw response body binary
      (skips JSON decoding). Useful when streaming large camera lists
      or feeding the body to a custom decoder.

  ## Examples

      {:ok, cameras} = UnifiApi.Protect.Cameras.list(client)

      {:ok, raw_binary} = UnifiApi.Protect.Cameras.list(client, raw: true)
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, opts \\ []) do
    Client.get(client, "#{prefix(client)}/v1/cameras", opts)
  end

  @doc """
  Gets a specific camera by ID.

  ## Examples

      {:ok, camera} = UnifiApi.Protect.Cameras.get(client, camera_id)
      camera["name"]  # => "Front Door"
      camera["state"] # => "CONNECTED"
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get(client, id) do
    Client.get(client, "#{prefix(client)}/v1/cameras/#{id!(id)}")
  end

  @doc """
  Updates camera settings.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Cameras.update(client, camera_id, %{
        name: "Front Door",
        micVolume: 80,
        videoMode: "highFps",
        ledSettings: %{isEnabled: false}
      })
  """
  @spec update(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def update(client, id, body) do
    Client.patch(client, "#{prefix(client)}/v1/cameras/#{id!(id)}", body)
  end

  @doc """
  Takes a camera snapshot. Returns JPEG binary data.

  ## Options

    * `:high_quality` — request a high-quality snapshot (boolean)

  ## Examples

      # Standard quality
      {:ok, jpeg} = UnifiApi.Protect.Cameras.snapshot(client, camera_id)
      File.write!("snapshot.jpg", jpeg)

      # High quality
      {:ok, jpeg} = UnifiApi.Protect.Cameras.snapshot(client, camera_id, high_quality: true)
  """
  @spec snapshot(Req.Request.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, UnifiApi.Error.t()}
  def snapshot(client, id, opts \\ []) do
    Client.get_raw(client, "#{prefix(client)}/v1/cameras/#{id!(id)}/snapshot", opts)
  end

  @doc """
  Starts a PTZ patrol on the given slot.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Cameras.ptz_patrol_start(client, camera_id, 0)
  """
  @spec ptz_patrol_start(Req.Request.t(), String.t(), integer()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  # `slot` is a path segment that never passes through
  # `Client.validate_id!/1` (that check is binary-only), so this guard is
  # the boundary that keeps an untrusted value — e.g. a string forwarded
  # straight from an HTTP query param such as `"0/../../users"` — out of
  # URL composition (CWE-22 / OWASP A03). Raising `FunctionClauseError`
  # here mirrors `validate_id!/1`'s raise-at-the-boundary contract.
  def ptz_patrol_start(client, id, slot) when is_integer(slot) and slot >= 0 do
    Client.post(
      client,
      "#{prefix(client)}/v1/cameras/#{id!(id)}/ptz/patrol/start/#{slot}",
      %{}
    )
  end

  @doc """
  Stops the current PTZ patrol.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Cameras.ptz_patrol_stop(client, camera_id)
  """
  @spec ptz_patrol_stop(Req.Request.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def ptz_patrol_stop(client, id) do
    Client.post(client, "#{prefix(client)}/v1/cameras/#{id!(id)}/ptz/patrol/stop", %{})
  end

  @doc """
  Moves the camera to a PTZ preset slot.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Cameras.ptz_goto(client, camera_id, 1)
  """
  @spec ptz_goto(Req.Request.t(), String.t(), integer()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  # Guarded for the same CWE-22 reason as `ptz_patrol_start/3` above.
  def ptz_goto(client, id, slot) when is_integer(slot) and slot >= 0 do
    Client.post(client, "#{prefix(client)}/v1/cameras/#{id!(id)}/ptz/goto/#{slot}", %{})
  end
end
