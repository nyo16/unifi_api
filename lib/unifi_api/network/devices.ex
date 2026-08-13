defmodule UnifiApi.Network.Devices do
  @moduledoc """
  UniFi Network API — device management.

  Manage adopted UniFi devices (APs, switches, gateways), view statistics,
  execute device and port actions, and list pending adoption requests.

  ## Device fields

    * `id`, `name`, `mac`, `ip`
    * `model`, `modelName` — hardware model identifiers (e.g. `"US-24-250W"`)
    * `state` — `"CONNECTED"`, `"CONNECTING"`, `"DISCONNECTED"`, `"PENDING"`,
      `"ADOPTING"`, `"PROVISIONING"`, `"UNREACHABLE"`, or `"UPGRADING"`
    * `adopted` — boolean
    * `firmwareVersion`
    * `uplink` — uplink interface metadata (deviceId, port idx, mac)
    * `features` — feature flags supported by this device
    * `interfaces` — `%{ "ports" => [...], "radios" => [...] }` for switches/APs

  ## Statistics fields (`get_statistics/3`)

    * `uptimeSec`, `lastHeartbeatAt`
    * `loadAverage1Min`, `loadAverage5Min`, `loadAverage15Min`
    * `cpuUtilizationPct`, `memoryUtilizationPct`
    * `uplink` — `%{ "rxRateBps" => _, "txRateBps" => _ }`
    * `interfaces` — per-port/radio counters (rx/tx packets, bytes, errors)

  ## Pending devices (`list_pending/2`)

  Devices reachable on the network that have not yet been adopted. Each entry
  has `mac`, `model`, `firmwareVersion`, and `ip`.
  """

  use UnifiApi.Resource, api: :network

  @doc """
  Lists all devices on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, devices} = UnifiApi.Network.Devices.list(client, site_id)
      {:ok, devices} = UnifiApi.Network.Devices.list(client, site_id, limit: 100)
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/devices", opts)
  end

  @doc """
  Gets a specific device by ID.

  ## Examples

      {:ok, device} = UnifiApi.Network.Devices.get(client, site_id, "device-uuid")
      device["name"]   # => "US-24-250W"
      device["state"]  # => "CONNECTED"
  """
  @spec get(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get(client, site_id, device_id) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/devices/#{id!(device_id)}"
    )
  end

  @doc """
  Adopts a new device into the site.

  ## Examples

      {:ok, _} = UnifiApi.Network.Devices.adopt(client, site_id, %{mac: "aa:bb:cc:dd:ee:ff"})
  """
  @spec adopt(Req.Request.t(), String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def adopt(client, site_id, body, opts \\ []) do
    Client.post(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/devices",
      body,
      opts
    )
  end

  @doc """
  Removes a device from the site.

  ## Examples

      {:ok, _} = UnifiApi.Network.Devices.remove(client, site_id, device_id)
  """
  @spec remove(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def remove(client, site_id, device_id) do
    Client.delete(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/devices/#{id!(device_id)}"
    )
  end

  @doc """
  Gets the latest statistics for a device.

  ## Examples

      {:ok, stats} = UnifiApi.Network.Devices.get_statistics(client, site_id, device_id)
  """
  @spec get_statistics(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get_statistics(client, site_id, device_id) do
    Client.get(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/devices/#{id!(device_id)}/statistics/latest"
    )
  end

  @doc """
  Executes an action on a device (e.g. restart, locate).

  ## Examples

      {:ok, _} = UnifiApi.Network.Devices.execute_action(client, site_id, device_id, %{action: "restart"})
      {:ok, _} = UnifiApi.Network.Devices.execute_action(client, site_id, device_id, %{action: "locate"})
  """
  @spec execute_action(Req.Request.t(), String.t(), String.t(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def execute_action(client, site_id, device_id, body) do
    Client.post(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/devices/#{id!(device_id)}/actions",
      body
    )
  end

  @doc """
  Executes an action on a specific device port (e.g. PoE cycle).

  ## Examples

      # Cycle PoE on port 3
      {:ok, _} = UnifiApi.Network.Devices.execute_port_action(client, site_id, device_id, 3, %{action: "cycle"})
  """
  @spec execute_port_action(Req.Request.t(), String.t(), String.t(), non_neg_integer(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  # `port_idx` is a path segment that never passes through `id!/1`
  # (`UnifiApi.Client.validate_id!/1` is binary-only), so this guard is
  # the boundary that keeps an untrusted value — e.g. a string forwarded
  # straight from an HTTP query param such as `"3/../../../users"` — out
  # of URL composition (CWE-22 / OWASP A03). Raising `FunctionClauseError`
  # here mirrors `id!/1`'s raise-at-the-boundary contract.
  def execute_port_action(client, site_id, device_id, port_idx, body)
      when is_integer(port_idx) and port_idx >= 0 do
    Client.post(
      client,
      "#{prefix(client)}/v1/sites/#{id!(site_id)}/devices/#{id!(device_id)}/interfaces/ports/#{port_idx}/actions",
      body
    )
  end

  @doc """
  Lists devices pending adoption (not site-scoped).

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, pending} = UnifiApi.Network.Devices.list_pending(client)
  """
  @spec list_pending(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list_pending(client, opts \\ []) do
    Client.get(client, "#{prefix(client)}/v1/pending-devices", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all devices on a site.

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

      UnifiApi.Network.Devices.stream(client, site_id, raise_errors: true)
      |> Stream.filter(& &1["state"] == "CONNECTED")
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix(client)}/v1/sites/#{id!(site_id)}/devices", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through pending devices.

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

    * `:max_pages` — halt after this many successful pages (default: unbounded).
    * `:max_items` — halt once this many items have been yielded (default: unbounded).
    * `:raise_errors` — raise `UnifiApi.StreamError` on error instead of
      yielding the error tuple (default: `false`).

  ## Examples

      UnifiApi.Network.Devices.stream_pending(client)
      |> Enum.to_list()
  """
  @spec stream_pending(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream_pending(client, opts \\ []) do
    Client.stream(client, "#{prefix(client)}/v1/pending-devices", opts)
  end
end
