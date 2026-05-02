#!/usr/bin/env elixir

# Saves a high-quality snapshot from every connected Protect camera into
# the snapshots/ directory.
#
# Run:
#   UNIFI_BASE_URL=https://192.168.1.1 \
#   UNIFI_API_KEY=your-api-key \
#   elixir examples/snapshots.exs

Mix.install([{:unifi_api, "~> 0.3"}])

base_url = System.fetch_env!("UNIFI_BASE_URL")
api_key = System.fetch_env!("UNIFI_API_KEY")

client = UnifiApi.new(base_url: base_url, api_key: api_key, verify_ssl: false)

File.mkdir_p!("snapshots")

{:ok, cameras} = UnifiApi.Protect.Cameras.list(client)

for camera <- cameras, camera["state"] == "CONNECTED" do
  case UnifiApi.Protect.Cameras.snapshot(client, camera["id"], high_quality: true) do
    {:ok, jpeg} ->
      name = camera["name"] |> String.replace(~r/[^\w]/, "_")
      path = "snapshots/#{name}.jpg"
      File.write!(path, jpeg)
      IO.puts("Saved #{path} (#{byte_size(jpeg)} bytes)")

    {:error, reason} ->
      IO.puts("Failed #{camera["name"]}: #{inspect(reason)}")
  end
end
