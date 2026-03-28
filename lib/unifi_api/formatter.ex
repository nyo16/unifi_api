defmodule UnifiApi.Formatter do
  @moduledoc """
  Pretty-prints API responses as colored ANSI tables in iex.

  Handles both raw lists and wrapped responses (`%{"data" => [...]}`).

  ## Examples

      {:ok, devices} = UnifiApi.Network.Devices.list(client, site_id)
      UnifiApi.Formatter.devices(devices)

      {:ok, clients} = UnifiApi.Network.Clients.list(client, site_id)
      UnifiApi.Formatter.clients(clients)
  """

  @doc """
  Prints a list of maps as a colored ANSI table.

  Accepts a plain list or a wrapped response (`%{"data" => [...]}`).

  ## Options

    * `:title` — optional title printed above the table
    * `:colors` — map of column names to color atoms (e.g. `%{"state" => :state}`)

  ## Examples

      UnifiApi.Formatter.table(devices, ["name", "macAddress", "state"], title: "Devices")

      UnifiApi.Formatter.table(clients, ["name", "ipAddress", "type"],
        title: "Connected Clients",
        colors: %{"type" => :type}
      )
  """
  @spec table(list(map()) | map(), list(String.t()), keyword()) :: :ok
  def table(data, columns, opts \\ [])

  def table(%{"data" => rows}, columns, opts) when is_list(rows) do
    table(rows, columns, opts)
  end

  def table(rows, columns, opts) when is_list(rows) and is_list(columns) do
    title = opts[:title]
    color_rules = opts[:colors] || %{}

    headers = columns
    data = Enum.map(rows, fn row -> Enum.map(columns, &get_value(row, &1)) end)
    widths = calculate_widths(headers, data)

    if title do
      IO.puts("\n#{IO.ANSI.bright()}#{IO.ANSI.cyan()}#{title}#{IO.ANSI.reset()}")
    end

    print_separator(widths)
    print_row(headers, widths, :header)
    print_separator(widths)

    Enum.each(data, fn row ->
      print_row_with_colors(row, headers, widths, color_rules)
    end)

    print_separator(widths)
    IO.puts("#{IO.ANSI.faint()}#{length(rows)} rows#{IO.ANSI.reset()}\n")
    :ok
  end

  @doc """
  Prints a single map as a colored key-value detail view.

  Handles wrapped responses (`%{"data" => %{...}}`).

  ## Examples

      {:ok, device} = UnifiApi.Network.Devices.get(client, site_id, device_id)
      UnifiApi.Formatter.detail(device)

      {:ok, nvr} = UnifiApi.Protect.NVR.get(client)
      UnifiApi.Formatter.detail(nvr, title: "NVR Info")
  """
  @spec detail(map(), keyword()) :: :ok
  def detail(data, opts \\ [])
  def detail(%{"data" => map}, opts) when is_map(map), do: detail(map, opts)

  def detail(map, opts) when is_map(map) do
    title = opts[:title]
    keys = opts[:keys] || Map.keys(map) |> Enum.sort()

    if title do
      IO.puts("\n#{IO.ANSI.bright()}#{IO.ANSI.cyan()}#{title}#{IO.ANSI.reset()}")
    end

    max_key_len = keys |> Enum.map(&String.length(to_string(&1))) |> Enum.max(fn -> 0 end)

    IO.puts("")

    Enum.each(keys, fn key ->
      value = format_value(map[key])
      padded_key = String.pad_trailing(to_string(key), max_key_len)
      IO.puts("  #{IO.ANSI.bright()}#{IO.ANSI.yellow()}#{padded_key}#{IO.ANSI.reset()}  #{value}")
    end)

    IO.puts("")
    :ok
  end

  @doc """
  Shortcut: prints devices as a pre-configured table.

  ## Examples

      {:ok, devices} = UnifiApi.Network.Devices.list(client, site_id)
      UnifiApi.Formatter.devices(devices)
  """
  @spec devices(list(map()) | map()) :: :ok
  def devices(data) do
    table(data, ["name", "macAddress", "model", "state", "ipAddress"],
      title: "Devices",
      colors: %{"state" => :state}
    )
  end

  @doc """
  Shortcut: prints clients as a pre-configured table.

  ## Examples

      {:ok, clients} = UnifiApi.Network.Clients.list(client, site_id)
      UnifiApi.Formatter.clients(clients)
  """
  @spec clients(list(map()) | map()) :: :ok
  def clients(data) do
    table(data, ["name", "ipAddress", "macAddress", "type"],
      title: "Connected Clients",
      colors: %{"type" => :type}
    )
  end

  @doc """
  Shortcut: prints cameras as a pre-configured table.

  ## Examples

      {:ok, cameras} = UnifiApi.Protect.Cameras.list(client)
      UnifiApi.Formatter.cameras(cameras)
  """
  @spec cameras(list(map()) | map()) :: :ok
  def cameras(data) do
    table(data, ["name", "modelKey", "state", "mac"],
      title: "Cameras",
      colors: %{"state" => :state}
    )
  end

  @doc """
  Shortcut: prints networks as a pre-configured table.

  ## Examples

      {:ok, networks} = UnifiApi.Network.Networks.list(client, site_id)
      UnifiApi.Formatter.networks(networks)
  """
  @spec networks(list(map()) | map()) :: :ok
  def networks(data) do
    table(data, ["name", "vlanId", "id"], title: "Networks")
  end

  @doc """
  Shortcut: prints sites as a pre-configured table.

  ## Examples

      {:ok, sites} = UnifiApi.Network.Sites.list(client)
      UnifiApi.Formatter.sites(sites)
  """
  @spec sites(list(map()) | map()) :: :ok
  def sites(data) do
    table(data, ["name", "id", "internalReference"], title: "Sites")
  end

  # --- Private ---

  defp get_value(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil -> ""
      val when is_map(val) -> inspect(val, pretty: false, limit: 3)
      val when is_list(val) -> inspect(val, pretty: false, limit: 3)
      val -> to_string(val)
    end
  end

  defp format_value(val) when is_map(val), do: inspect(val, pretty: true, limit: 10)
  defp format_value(val) when is_list(val), do: inspect(val, pretty: true, limit: 10)
  defp format_value(nil), do: "#{IO.ANSI.faint()}nil#{IO.ANSI.reset()}"
  defp format_value(val), do: to_string(val)

  defp calculate_widths(headers, data) do
    initial = Enum.map(headers, &String.length(&1))

    Enum.reduce(data, initial, fn row, widths ->
      Enum.zip(row, widths)
      |> Enum.map(fn {cell, w} -> max(String.length(cell), w) end)
    end)
  end

  defp print_separator(widths) do
    line = Enum.map_join(widths, "-+-", &String.duplicate("-", &1 + 2))
    IO.puts("#{IO.ANSI.faint()}+-#{line}-+#{IO.ANSI.reset()}")
  end

  defp print_row(cells, widths, :header) do
    row =
      Enum.zip(cells, widths)
      |> Enum.map_join(" | ", fn {cell, w} ->
        "#{IO.ANSI.bright()}#{IO.ANSI.white()}#{String.pad_trailing(cell, w)}#{IO.ANSI.reset()}"
      end)

    IO.puts("| #{row} |")
  end

  defp print_row_with_colors(cells, headers, widths, color_rules) do
    row =
      Enum.zip([cells, headers, widths])
      |> Enum.map_join(" | ", fn {cell, header, w} ->
        color = get_color(cell, Map.get(color_rules, header))
        "#{color}#{String.pad_trailing(cell, w)}#{IO.ANSI.reset()}"
      end)

    IO.puts("| #{row} |")
  end

  defp get_color(value, :state) do
    case value do
      v when v in ["CONNECTED", "ONLINE"] -> IO.ANSI.green()
      v when v in ["CONNECTING", "UPDATING"] -> IO.ANSI.yellow()
      v when v in ["DISCONNECTED", "OFFLINE"] -> IO.ANSI.red()
      _ -> ""
    end
  end

  defp get_color(value, :type) do
    case value do
      "WIRELESS" -> IO.ANSI.magenta()
      "WIRED" -> IO.ANSI.blue()
      "VPN" -> IO.ANSI.cyan()
      "TELEPORT" -> IO.ANSI.yellow()
      _ -> ""
    end
  end

  defp get_color(_value, _), do: ""
end
