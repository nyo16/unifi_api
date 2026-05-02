#!/usr/bin/env elixir

# Protect events: pulls every motion / smartDetect event from the last
# hour and saves each one's thumbnail to disk. Demonstrates the
# binary-payload endpoints (UnifiApi.Protect.Events.thumbnail/3).
#
# Run:
#   UNIFI_BASE_URL=https://192.168.1.1 \
#   UNIFI_USERNAME=admin \
#   UNIFI_PASSWORD=secret \
#   elixir examples/protect_events.exs

Mix.install([{:unifi_api, "~> 0.3"}])

base_url = System.fetch_env!("UNIFI_BASE_URL")
username = System.fetch_env!("UNIFI_USERNAME")
password = System.fetch_env!("UNIFI_PASSWORD")

client = UnifiApi.new(base_url: base_url, verify_ssl: false)
{:ok, authed} = UnifiApi.Auth.Cookie.login(client, username, password, style: :udm)

File.mkdir_p!("protect_events")

start = System.os_time(:millisecond) - 60 * 60 * 1000

{:ok, events} =
  UnifiApi.Protect.Events.list(authed,
    start: start,
    types: ["motion", "smartDetectZone"],
    limit: 200
  )

IO.puts("Pulled #{length(events)} events from the last hour.")

for ev <- events do
  case UnifiApi.Protect.Events.thumbnail(authed, ev["id"], width: 640) do
    {:ok, jpeg} ->
      path = "protect_events/#{ev["id"]}.jpg"
      File.write!(path, jpeg)
      IO.puts("Saved #{path} (#{byte_size(jpeg)} bytes)")

    {:error, reason} ->
      IO.puts("Skipped #{ev["id"]}: #{inspect(reason)}")
  end
end
