#!/usr/bin/env elixir

# Dashboard scraper: pulls a snapshot of sites, devices, clients, networks,
# WiFi, WANs, and Protect cameras/sensors/lights, then writes dashboard.json.
#
# Run:
#   UNIFI_BASE_URL=https://192.168.1.1 \
#   UNIFI_API_KEY=your-api-key \
#   elixir examples/dashboard.exs

Mix.install([{:unifi_api, "~> 0.3"}])

base_url = System.fetch_env!("UNIFI_BASE_URL")
api_key = System.fetch_env!("UNIFI_API_KEY")

client = UnifiApi.new(base_url: base_url, api_key: api_key, verify_ssl: false)

{:ok, info} = UnifiApi.Network.Info.get_info(client)

sites_data =
  UnifiApi.Network.Sites.stream(client)
  |> Enum.map(fn site ->
    sid = site["id"]
    clients = UnifiApi.Network.Clients.stream(client, sid) |> Enum.to_list()

    client_breakdown =
      clients
      |> Enum.group_by(& &1["type"])
      |> Map.new(fn {type, list} -> {type, length(list)} end)

    devices = UnifiApi.Network.Devices.stream(client, sid) |> Enum.to_list()

    %{
      site_id: sid,
      site_name: site["name"],
      clients: %{
        total: length(clients),
        wired: client_breakdown["WIRED"] || 0,
        wireless: client_breakdown["WIRELESS"] || 0,
        vpn: client_breakdown["VPN"] || 0,
        teleport: client_breakdown["TELEPORT"] || 0
      },
      devices: %{
        total: length(devices),
        connected: Enum.count(devices, &(&1["state"] == "CONNECTED")),
        disconnected: Enum.count(devices, &(&1["state"] == "DISCONNECTED"))
      },
      networks:
        UnifiApi.Network.Networks.stream(client, sid)
        |> Enum.map(&Map.take(&1, ["id", "name", "vlanId"])),
      ssids:
        UnifiApi.Network.Wifi.stream(client, sid)
        |> Enum.map(&Map.take(&1, ["id", "name", "enabled"])),
      wans:
        UnifiApi.Network.Resources.stream_wans(client, sid)
        |> Enum.map(&Map.take(&1, ["id", "name", "status"]))
    }
  end)

{:ok, cameras} = UnifiApi.Protect.Cameras.list(client)
{:ok, sensors} = UnifiApi.Protect.Sensors.list(client)
{:ok, lights} = UnifiApi.Protect.Lights.list(client)
{:ok, nvr} = UnifiApi.Protect.NVR.get(client)

protect_data = %{
  nvr: Map.take(nvr, ["id", "name", "modelKey"]),
  cameras: %{
    total: length(cameras),
    connected: Enum.count(cameras, &(&1["state"] == "CONNECTED"))
  },
  sensors: %{
    total: length(sensors),
    open_doors: Enum.count(sensors, & &1["isOpened"]),
    motion_detected: Enum.count(sensors, & &1["isMotionDetected"])
  },
  lights: %{
    total: length(lights),
    on: Enum.count(lights, & &1["isLightOn"])
  }
}

dashboard = %{
  controller_version: info["applicationVersion"],
  scraped_at: DateTime.utc_now(),
  sites: sites_data,
  protect: protect_data
}

File.write!("dashboard.json", JSON.encode!(dashboard))
IO.puts("Wrote dashboard.json (#{length(sites_data)} sites)")
