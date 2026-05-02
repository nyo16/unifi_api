#!/usr/bin/env elixir

# Quickstart: list sites, devices, and clients on a UniFi controller.
#
# Run:
#   UNIFI_BASE_URL=https://192.168.1.1 \
#   UNIFI_API_KEY=your-api-key \
#   elixir examples/quickstart.exs
#
# For Cloud Key controllers, set:
#   UNIFI_NETWORK_PATH=/integration

Mix.install([{:unifi_api, "~> 0.3"}])

base_url = System.fetch_env!("UNIFI_BASE_URL")
api_key = System.fetch_env!("UNIFI_API_KEY")
network_path = System.get_env("UNIFI_NETWORK_PATH", "/proxy/network/integration")

Application.put_env(:unifi_api, :network_path, network_path)

client = UnifiApi.new(base_url: base_url, api_key: api_key, verify_ssl: false)

{:ok, info} = UnifiApi.Network.Info.get_info(client)
IO.puts("Controller version: #{info["applicationVersion"]}")

{:ok, sites} = UnifiApi.Network.Sites.list(client)
IO.puts("\nSites (#{length(sites)}):")
UnifiApi.Formatter.sites(sites)

[%{"id" => first_site} = site | _] = sites
IO.puts("\nDevices on #{site["name"]}:")

UnifiApi.Network.Devices.stream(client, first_site)
|> Enum.to_list()
|> UnifiApi.Formatter.devices()

IO.puts("\nClients on #{site["name"]}:")

UnifiApi.Network.Clients.stream(client, first_site)
|> Enum.to_list()
|> UnifiApi.Formatter.clients()
