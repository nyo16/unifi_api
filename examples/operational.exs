#!/usr/bin/env elixir

# Operational data: cookie-auth login + recent events, active alarms, and
# live wireless client stats. Demonstrates the v1 endpoint surface that
# requires UnifiApi.Auth.Cookie (not the integration API key).
#
# Run:
#   UNIFI_BASE_URL=https://192.168.1.1 \
#   UNIFI_USERNAME=admin \
#   UNIFI_PASSWORD=secret \
#   UNIFI_SITE=default \
#   elixir examples/operational.exs

Mix.install([{:unifi_api, "~> 0.3"}])

base_url = System.fetch_env!("UNIFI_BASE_URL")
username = System.fetch_env!("UNIFI_USERNAME")
password = System.fetch_env!("UNIFI_PASSWORD")
site = System.get_env("UNIFI_SITE", "default")

client = UnifiApi.new(base_url: base_url, verify_ssl: false)

{:ok, info} = UnifiApi.detect(client)
IO.puts("Controller style: #{info.style}")

# Apply detected paths so v1 calls land in the right place.
Application.put_env(:unifi_api, :v1_path, info.v1_prefix)

{:ok, authed} = UnifiApi.Auth.Cookie.login(client, username, password, style: info.style)
IO.puts("Logged in as #{username}.\n")

# Recent events
{:ok, events} = UnifiApi.Network.Events.list(authed, site, within_hours: 1, limit: 25)
UnifiApi.Formatter.events(events)

# Active alarms only
{:ok, alarms} = UnifiApi.Network.Alarms.list(authed, site, archived: false)
UnifiApi.Formatter.alarms(alarms)

# Live wireless client signal quality
{:ok, clients} = UnifiApi.Network.ClientsLive.list(authed, site)

worst =
  clients
  |> Enum.reject(& &1["is_wired"])
  |> Enum.sort_by(& &1["signal"])
  |> Enum.take(10)

IO.puts("Worst-RSSI wireless clients:")
UnifiApi.Formatter.clients_live(worst)
