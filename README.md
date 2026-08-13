# UnifiApi

[![CI](https://github.com/nyo16/unifi_api/actions/workflows/ci.yml/badge.svg)](https://github.com/nyo16/unifi_api/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/unifi_api.svg)](https://hex.pm/packages/unifi_api)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/unifi_api)
[![License](https://img.shields.io/hexpm/l/unifi_api.svg)](https://github.com/nyo16/unifi_api/blob/master/LICENSE)

Elixir HTTP client for **UniFi Dream Machine** APIs, covering both the **Network API** (v10.1.84) and the **Protect API** (v6.2.88). Built on [Req](https://hexdocs.pm/req).

## Installation

Add `unifi_api` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:unifi_api, "~> 0.4.0"}
  ]
end
```

`unifi_api` is a library and ships **no Application callback** — it does
not start a supervision tree of its own. Consumers that need the
auto-rotating cookie/CSRF session (`UnifiApi.Auth.Session`) add it to
their own supervision tree:

```elixir
children = [
  {UnifiApi.Auth.Session,
   name: MyApp.UnifiSession,
   client: UnifiApi.new(base_url: "https://192.168.1.1", api_key: "..."),
   relogin: fn -> UnifiApi.Auth.Cookie.login(...) end,
   style: :udm}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Stateless one-shot scripts don't need any supervision — just call
`UnifiApi.Auth.Cookie.login/4` directly (see "Operational Data").

## Configuration

### Application config

```elixir
# config/config.exs
config :unifi_api,
  base_url: "https://192.168.1.1",
  api_key: "your-api-key",
  # Secure by default (CWE-295 / OWASP A02). Set to `false` only for
  # self-signed controllers on a trusted network, or pin the leaf cert
  # with `cert_fingerprints` — see "Self-Signed Certificates".
  verify_ssl: true,
  # UDM defaults — for Cloud Key, set both to "/integration"
  network_path: "/proxy/network/integration",
  protect_path: "/proxy/protect/integration"
```

### Environment variables

```elixir
# config/runtime.exs
config :unifi_api,
  base_url: System.get_env("UNIFI_BASE_URL", "https://192.168.1.1"),
  api_key: System.get_env("UNIFI_API_KEY", ""),
  # `verify_ssl: true` by default (secure-by-default). To disable:
  #   - set `UNIFI_VERIFY_SSL=false`, or
  #   - set the last-resort escape hatch `UNIFI_INSECURE_TLS=1`.
  # Both are insecure; prefer `cert_fingerprints` for self-signed controllers.
  verify_ssl: System.get_env("UNIFI_VERIFY_SSL", "true") == "true" and
              System.get_env("UNIFI_INSECURE_TLS", "0") not in ["1", "true"],
  network_path: System.get_env("UNIFI_NETWORK_PATH", "/proxy/network/integration"),
  protect_path: System.get_env("UNIFI_PROTECT_PATH", "/proxy/protect/integration")
```

### Path prefixes

The four API path prefixes are resolved once when the client is built and
carried on the client struct, so clients for different controller flavours
coexist in the same VM.

On **UDM / UDM Pro / UDM SE** (UniFi OS) the APIs run behind a reverse proxy;
on **Cloud Key** and standalone controllers they sit at the root. Pick the
flavour with `:style`:

```elixir
udm = UnifiApi.new(base_url: udm_url, api_key: k1, style: :udm)          # default
cloud_key = UnifiApi.new(base_url: ck_url, api_key: k2, style: :cloud_key)
```

| API | `:udm` (default) | `:cloud_key` | Override option | Env var |
|-----|------------------|--------------|-----------------|---------|
| Network | `/proxy/network/integration` | `/integration` | `:network_path` | `UNIFI_NETWORK_PATH` |
| Protect | `/proxy/protect/integration` | `/integration` | `:protect_path` | `UNIFI_PROTECT_PATH` |
| Network v1 (cookie auth) | `/proxy/network` | `""` | `:v1_path` | `UNIFI_V1_PATH` |
| Protect v1 (cookie auth) | `/proxy/protect` | `/protect` | `:protect_v1_path` | — |

Not sure which flavour you have? `UnifiApi.detect/1` probes the controller and
its `:style` feeds straight back into `new/1`:

```elixir
{:ok, info} = UnifiApi.detect(UnifiApi.new(base_url: url))
client = UnifiApi.new(base_url: url, api_key: key, style: info.style)
```

Setting the paths in application config still works and is honoured when no
`:style` is given, but it is global — it cannot describe two controllers at
once:

```elixir
config :unifi_api,
  network_path: "/integration",
  protect_path: "/integration"
```

Resolution order, highest first: an explicit `:network_path` (etc.) option,
the `:style` preset, the application env key, then the `:udm` default.

### Runtime override

Pass options directly when creating a client to override application config:

```elixir
client = UnifiApi.new(
  base_url: "https://192.168.0.1",
  api_key: "my-api-key",
  # verify_ssl: true is the default; only set false with a self-signed
  # controller on a trusted network, or use cert_fingerprints.
  cert_fingerprints: ["sha256:AB:CD:EF:..."]
)
```

### Timeouts, retries, and pools

All optional, with production-safe defaults:

| Option | Default | Notes |
|--------|---------|-------|
| `:connect_timeout` | `5_000` | TCP/TLS connect. Mint's own default is 30s, which makes a black-holed controller IP block ~61s per call. Also `config :unifi_api, connect_timeout: ms`. |
| `:receive_timeout` | `30_000` | Time to first response. |
| `:pool_timeout` | `5_000` | Connection checkout. |
| `:max_retries` | `1` | Retries transient failures on GET/HEAD only. A server-supplied `Retry-After` is honoured but clamped to 300s. |
| `:finch` | — | Name of a Finch pool you started yourself. Mutually exclusive with the TLS and connect-timeout options, which then belong on your pool; combining them raises instead of silently dropping your transport settings. |

```elixir
client = UnifiApi.new(
  base_url: "https://192.168.0.1",
  api_key: "my-api-key",
  connect_timeout: 2_000,
  receive_timeout: 10_000
)
```

## Quick Start

```elixir
# Create a client (uses application config)
client = UnifiApi.new()

# Or with explicit options
client = UnifiApi.new(base_url: "https://192.168.1.1", api_key: "my-key")

# Check the controller version
{:ok, info} = UnifiApi.Network.Info.get_info(client)
# => {:ok, %{"applicationVersion" => "10.1.84"}}

# List all sites
{:ok, sites} = UnifiApi.Network.Sites.list(client)

# List devices on a site
{:ok, devices} = UnifiApi.Network.Devices.list(client, "site-uuid")

# List Protect cameras
{:ok, cameras} = UnifiApi.Protect.Cameras.list(client)
```

## Quality-of-Life Helpers

A few small utilities that show up everywhere:

```elixir
# Reachability — works against both API-key and cookie-authed clients
:ok = UnifiApi.ping(client)

# Detect controller style and the matching path conventions
{:ok, %{style: :udm, network_prefix: _, v1_prefix: _, auth_path: _}} =
  UnifiApi.detect(client)

# Resolve a site by display name without listing manually
{:ok, %{"id" => site_id}} = UnifiApi.Network.Sites.find_by_name(client, "HQ")
{:ok, default} = UnifiApi.Network.Sites.find_by_internal_reference(client, "default")

# Unix-millisecond helpers for time-window queries
import UnifiApi.Time

UnifiApi.Protect.Events.list(authed,
  start: hours_ago(1),
  end: now_ms(),
  types: ["motion"]
)
```

## Network API

All Network API functions require a `site_id` (except `Info`, `Resources.list_dpi_categories/2`, `Resources.list_dpi_applications/2`, `Resources.list_countries/2`, and `Devices.list_pending/2`).

### Sites

```elixir
{:ok, sites} = UnifiApi.Network.Sites.list(client)
# => {:ok, [%{"id" => "abc-123", "name" => "Default", "internalReference" => "default"}]}
```

### Devices

```elixir
# List all devices on a site
{:ok, devices} = UnifiApi.Network.Devices.list(client, site_id)

# Get a specific device
{:ok, device} = UnifiApi.Network.Devices.get(client, site_id, device_id)

# Get latest device statistics
{:ok, stats} = UnifiApi.Network.Devices.get_statistics(client, site_id, device_id)

# Adopt a new device
{:ok, _} = UnifiApi.Network.Devices.adopt(client, site_id, %{mac: "aa:bb:cc:dd:ee:ff"})

# Execute a device action (restart, locate, etc.)
{:ok, _} = UnifiApi.Network.Devices.execute_action(client, site_id, device_id, %{action: "restart"})

# Execute a port action (PoE cycle, etc.)
{:ok, _} = UnifiApi.Network.Devices.execute_port_action(client, site_id, device_id, 3, %{action: "cycle"})

# Remove a device
{:ok, _} = UnifiApi.Network.Devices.remove(client, site_id, device_id)

# List pending devices (not site-scoped)
{:ok, pending} = UnifiApi.Network.Devices.list_pending(client)
```

### Clients

```elixir
# List connected clients
{:ok, clients} = UnifiApi.Network.Clients.list(client, site_id)
# Each client has: type (WIRED/WIRELESS/VPN/TELEPORT), id, name, connectedAt, ipAddress, access
```

### Networks

```elixir
# List all networks
{:ok, networks} = UnifiApi.Network.Networks.list(client, site_id)

# Get a specific network
{:ok, network} = UnifiApi.Network.Networks.get(client, site_id, network_id)

# Create a network
{:ok, network} = UnifiApi.Network.Networks.create(client, site_id, %{
  name: "Guest VLAN",
  vlanId: 100
})

# Update a network
{:ok, _} = UnifiApi.Network.Networks.update(client, site_id, network_id, %{name: "New Name"})

# Delete a network
{:ok, _} = UnifiApi.Network.Networks.delete(client, site_id, network_id)
```

### WiFi

```elixir
# List WiFi broadcasts (SSIDs)
{:ok, ssids} = UnifiApi.Network.Wifi.list(client, site_id)
```

### Firewall

```elixir
# --- Zones ---
{:ok, zones} = UnifiApi.Network.Firewall.list_zones(client, site_id)
{:ok, zone} = UnifiApi.Network.Firewall.get_zone(client, site_id, zone_id)
{:ok, zone} = UnifiApi.Network.Firewall.create_zone(client, site_id, %{name: "DMZ", networkIds: [net_id]})
{:ok, _} = UnifiApi.Network.Firewall.update_zone(client, site_id, zone_id, %{name: "DMZ-Updated"})
{:ok, _} = UnifiApi.Network.Firewall.delete_zone(client, site_id, zone_id)

# --- Policies ---
{:ok, policies} = UnifiApi.Network.Firewall.list_policies(client, site_id)
{:ok, policy} = UnifiApi.Network.Firewall.get_policy(client, site_id, policy_id)
{:ok, policy} = UnifiApi.Network.Firewall.create_policy(client, site_id, %{
  name: "Block IoT to LAN",
  enabled: true,
  action: "BLOCK",
  source: %{zoneId: iot_zone_id},
  destination: %{zoneId: lan_zone_id}
})
{:ok, _} = UnifiApi.Network.Firewall.update_policy(client, site_id, policy_id, %{enabled: false})
{:ok, _} = UnifiApi.Network.Firewall.delete_policy(client, site_id, policy_id)
```

### Hotspot Vouchers

```elixir
# List all vouchers
{:ok, vouchers} = UnifiApi.Network.Hotspot.list_vouchers(client, site_id)

# Get a specific voucher
{:ok, voucher} = UnifiApi.Network.Hotspot.get_voucher(client, site_id, voucher_id)

# Create vouchers (1-1000 at a time)
{:ok, vouchers} = UnifiApi.Network.Hotspot.create_vouchers(client, site_id, %{
  count: 10,
  name: "Event Pass",
  timeLimitMinutes: 1440,
  authorizedGuestLimit: 1,
  dataUsageLimitMBytes: 500,
  rxRateLimitKbps: 5000,
  txRateLimitKbps: 1000
})

# Delete a specific voucher
{:ok, _} = UnifiApi.Network.Hotspot.delete_voucher(client, site_id, voucher_id)

# Delete all vouchers
{:ok, _} = UnifiApi.Network.Hotspot.delete_vouchers(client, site_id)
```

### ACL Rules

```elixir
# List ACL rules
{:ok, rules} = UnifiApi.Network.ACL.list(client, site_id)

# Create an ACL rule
{:ok, rule} = UnifiApi.Network.ACL.create(client, site_id, %{
  type: "IPV4",
  name: "Block SSH",
  enabled: true,
  action: "BLOCK",
  protocolFilter: %{protocol: "TCP", dstPort: 22}
})

# Update and delete
{:ok, _} = UnifiApi.Network.ACL.update(client, site_id, rule_id, %{enabled: false})
{:ok, _} = UnifiApi.Network.ACL.delete(client, site_id, rule_id)

# Manage rule ordering
{:ok, ordering} = UnifiApi.Network.ACL.get_ordering(client, site_id)
{:ok, _} = UnifiApi.Network.ACL.update_ordering(client, site_id, %{ids: ["rule-1", "rule-2"]})
```

### DNS Policies

```elixir
# List DNS policies
{:ok, policies} = UnifiApi.Network.DNS.list(client, site_id)

# Create a DNS record
{:ok, policy} = UnifiApi.Network.DNS.create(client, site_id, %{
  type: "A_RECORD",
  name: "app.local",
  value: "192.168.1.50"
})

# Supported types: A_RECORD, AAAA_RECORD, CNAME_RECORD, MX_RECORD,
#                  TXT_RECORD, SRV_RECORD, FORWARD_DOMAIN
```

### Traffic Matching

```elixir
{:ok, lists} = UnifiApi.Network.TrafficMatching.list(client, site_id)
# Types: PORTS, IPV4_ADDRESSES, IPV6_ADDRESSES
```

### Supporting Resources

```elixir
# WAN interfaces
{:ok, wans} = UnifiApi.Network.Resources.list_wans(client, site_id)

# VPN
{:ok, tunnels} = UnifiApi.Network.Resources.list_vpn_tunnels(client, site_id)
{:ok, servers} = UnifiApi.Network.Resources.list_vpn_servers(client, site_id)

# RADIUS
{:ok, profiles} = UnifiApi.Network.Resources.list_radius_profiles(client, site_id)

# Device tags
{:ok, tags} = UnifiApi.Network.Resources.list_device_tags(client, site_id)

# DPI (not site-scoped)
{:ok, categories} = UnifiApi.Network.Resources.list_dpi_categories(client)
{:ok, apps} = UnifiApi.Network.Resources.list_dpi_applications(client)

# Countries (not site-scoped)
{:ok, countries} = UnifiApi.Network.Resources.list_countries(client)
```

## Protect API

Protect endpoints are **not** site-scoped.

### Cameras

```elixir
# List all cameras
{:ok, cameras} = UnifiApi.Protect.Cameras.list(client)

# Get a specific camera
{:ok, camera} = UnifiApi.Protect.Cameras.get(client, camera_id)

# Update camera settings
{:ok, _} = UnifiApi.Protect.Cameras.update(client, camera_id, %{
  name: "Front Door",
  micVolume: 80,
  videoMode: "highFps",
  ledSettings: %{isEnabled: false}
})

# Take a snapshot (returns JPEG binary)
{:ok, jpeg} = UnifiApi.Protect.Cameras.snapshot(client, camera_id)
File.write!("snapshot.jpg", jpeg)

# High quality snapshot
{:ok, jpeg} = UnifiApi.Protect.Cameras.snapshot(client, camera_id, high_quality: true)

# PTZ controls
{:ok, _} = UnifiApi.Protect.Cameras.ptz_goto(client, camera_id, 1)           # Go to preset slot 1
{:ok, _} = UnifiApi.Protect.Cameras.ptz_patrol_start(client, camera_id, 0)   # Start patrol slot 0
{:ok, _} = UnifiApi.Protect.Cameras.ptz_patrol_stop(client, camera_id)       # Stop patrol
```

### NVR

```elixir
{:ok, nvr} = UnifiApi.Protect.NVR.get(client)
# => {:ok, %{"id" => "...", "name" => "UNVR", "doorbellSettings" => %{...}}}
```

### Viewers

```elixir
{:ok, viewers} = UnifiApi.Protect.Viewers.list(client)
{:ok, viewer} = UnifiApi.Protect.Viewers.get(client, viewer_id)
{:ok, _} = UnifiApi.Protect.Viewers.update(client, viewer_id, %{liveview: liveview_id})
```

### Liveviews

```elixir
{:ok, liveviews} = UnifiApi.Protect.Liveviews.list(client)
# Each has: id, name, isDefault, isGlobal, owner, layout (1-26), slots
```

### Sensors

```elixir
{:ok, sensors} = UnifiApi.Protect.Sensors.list(client)
# Each has: id, name, state, mountType, batteryStatus, stats,
#           isOpened, isMotionDetected, temperature/humidity/light/leak settings
```

### Lights

```elixir
{:ok, lights} = UnifiApi.Protect.Lights.list(client)
# Each has: id, name, state, isDark, isLightOn, lastMotion,
#           lightModeSettings, lightDeviceSettings, camera
```

### Chimes

```elixir
{:ok, chimes} = UnifiApi.Protect.Chimes.list(client)
# Each has: id, name, state, cameraIds, ringSettings
```

## Operational Data (Legacy v1 / v2 API)

The integration API doesn't expose the operational and monitoring data
ops users actually want — events, alarms, IDS detections, rich live
wireless stats, topology, traffic, WAN health, and so on. These live on
the legacy `/api/s/{site}/...` and `/v2/api/site/{site}/...` paths and
require **cookie + CSRF authentication** rather than `x-api-key`.

### Authenticate (one-shot scripts)

```elixir
# Build an unauthenticated client, then log in.
client = UnifiApi.new(base_url: "https://192.168.1.1",
  cert_fingerprints: ["sha256:AB:CD:EF:..."])

{:ok, authed} = UnifiApi.Auth.Cookie.login(client, "admin", "password",
  style: :udm  # or :cloud_key
)
```

If you're not sure which style your controller uses, probe it first:

```elixir
{:ok, info} = UnifiApi.detect(client)
{:ok, authed} = UnifiApi.Auth.Cookie.login(client, user, pass, style: info.style)
```

For Cloud Key controllers pass `style: :cloud_key` when building the client,
which sets the v1 prefix to `""` (the UDM default is `/proxy/network`). See
"Path prefixes".

### Authenticate (long-running app)

For pollers and supervised processes that need cookie auth over hours
or days, `UnifiApi.Auth.Cookie.login/4`'s static request struct goes
stale when the controller rotates the CSRF token. Use
`UnifiApi.Auth.Session` instead — a supervised GenServer that holds
the cookie + CSRF state and auto-rotates the token from response
headers:

```elixir
# Fingerprints for the controller's self-signed cert, comma-separated.
fingerprints =
  System.get_env("UNIFI_CERT_FINGERPRINTS", "") |> String.split(",", trim: true)

base = UnifiApi.new(base_url: "https://192.168.1.1", cert_fingerprints: fingerprints)

children = [
  {UnifiApi.Auth.Session,
   name: MyApp.UnifiSession,
   client: base,
   # Preferred over :username / :password (CWE-522): the session calls this
   # only when a fresh login is needed and never holds the plaintext itself.
   relogin: fn ->
     UnifiApi.Auth.Cookie.login(
       base,
       System.fetch_env!("UNIFI_USERNAME"),
       System.fetch_env!("UNIFI_PASSWORD"),
       style: :udm
     )
   end,
   style: :udm}
]

Supervisor.start_link(children, strategy: :one_for_one)

# Anywhere in your app — a lock-free read, no call into the GenServer:
authed = UnifiApi.Auth.Session.client(MyApp.UnifiSession)
{:ok, events} = UnifiApi.Network.Events.list(authed, "default")
```

Every request through `authed` pulls the current cookies + CSRF from
the GenServer at send time and writes back any rotated token captured
from the response. `Session.refresh/1` and `Session.relogin/1` are
escape hatches for the rare case the auto-rotation misses.

### Available modules

| Module | Endpoint | Purpose |
|--------|----------|---------|
| `Network.Events` | `/stat/event` | Client/AP/system events |
| `Network.Alarms` | `/list/alarm` | Active and archived alarms |
| `Network.Anomalies` | `/stat/anomalies` | Diagnostic anomalies |
| `Network.IDS` | `/stat/ips/event` | IDS / IPS detections |
| `Network.RogueAP` | `/stat/rogueap`, `/rest/rogueknown` | Neighbouring / rogue APs |
| `Network.ClientsLive` | `/stat/sta`, `/stat/alluser` | Rich wireless stats; offline history |
| `Network.ClientsHistory` | `/v2/.../clients/history` | Searchable client history |
| `Network.DPI` | `/stat/sitedpi`, `/stat/stadpi` | DPI by site / per-client |
| `Network.Traffic` | `/v2/.../traffic`, `/country-traffic` | Time-series by client / country |
| `Network.SystemLog` | `/v2/.../system-log/all` | Controller system log |
| `Network.ActiveLeases` | `/v2/.../active-leases` | Live DHCP table |
| `Network.WAN` | `/v2/.../wan/...`, `/wan-slas` | WAN config, ISP status, SLAs |
| `Network.PortAnomalies` | `/v2/.../ports/port-anomalies` | Switch port anomalies |
| `Network.UPS` | `/stat/ups-devices` | UPS battery / load |
| `Network.PortForward` | `/rest/portforward` | NAT port forward CRUD |
| `Network.Dashboard` | `/v2/.../aggregated-dashboard` | One-shot dashboard payload |
| `Network.Topology` | `/v2/.../topology` | Topology graph |
| `Protect.Events` | `/proxy/protect/api/events` | Motion, ring, smartDetect events + thumbnails |

### Quick example

```elixir
# Recent events (last 24 hours, up to 1000)
{:ok, events} = UnifiApi.Network.Events.list(authed, "default",
  within_hours: 24, limit: 1000)

# Worst-RSSI wireless clients right now
{:ok, clients} = UnifiApi.Network.ClientsLive.list(authed, "default")
worst =
  clients
  |> Enum.reject(& &1["is_wired"])
  |> Enum.sort_by(& &1["signal"])
  |> Enum.take(10)

# All Protect motion events in the last hour, with thumbnails
hour_ago = System.os_time(:millisecond) - 60 * 60 * 1000
{:ok, motion} =
  UnifiApi.Protect.Events.list(authed, start: hour_ago, types: ["motion"])

for ev <- motion do
  {:ok, jpeg} = UnifiApi.Protect.Events.thumbnail(authed, ev["id"])
  File.write!("event-#{ev["id"]}.jpg", jpeg)
end
```

### DPI with names

The legacy DPI endpoints return numeric `cat` and `app` IDs only.
Combine them with the integration-API category / application lists
via `UnifiApi.Network.DPI.with_names/2`:

```elixir
# These don't change often — fetch once, reuse:
{:ok, categories} = UnifiApi.Network.Resources.list_dpi_categories(client)
{:ok, applications} = UnifiApi.Network.Resources.list_dpi_applications(client)

# Then on every poll:
{:ok, dpi} = UnifiApi.Network.DPI.by_site(authed, "default")

named =
  UnifiApi.Network.DPI.with_names(dpi,
    categories: categories,
    applications: applications
  )

# Top 10 apps by tx_bytes
named
|> Enum.flat_map(& &1["by_app"])
|> Enum.sort_by(& &1["tx_bytes"], :desc)
|> Enum.take(10)
|> Enum.map(&{&1["application_name"], &1["tx_bytes"]})
```

> **Note:** v1 / v2 endpoint shapes are documented from community
> sources (primarily `unpoller/unpoller`). They have not been exercised
> end-to-end against live UDM Pro / Cloud Key hardware in v0.4.0. Please
> file an issue with controller model and firmware version if anything
> looks off — most fixes will be one-line tweaks.

## Streaming & Pagination

Every list endpoint has a `stream` variant that returns a lazy `Stream` powered by
`Stream.resource/3`. Pages are fetched on demand — no data is pulled until you
consume the stream with `Enum` or `Stream` functions.

### Lazy streaming (recommended)

```elixir
# Stream ALL devices across pages — fetches 200 per page automatically
UnifiApi.Network.Devices.stream(client, site_id)
|> Enum.to_list()

# Only the first page is fetched
UnifiApi.Network.Devices.stream(client, site_id)
|> Enum.take(5)

# Filter + stream — composable with the full Stream/Enum API
UnifiApi.Network.Clients.stream(client, site_id, filter: "type.eq(WIRELESS)")
|> Stream.map(& &1["name"])
|> Enum.to_list()

# Count all clients without loading them all into memory at once
UnifiApi.Network.Clients.stream(client, site_id)
|> Enum.count()

# Custom page size
UnifiApi.Network.Devices.stream(client, site_id, limit: 50)
|> Enum.to_list()

# Stream firewall policies, vouchers, ACL rules, DNS, etc.
UnifiApi.Network.Firewall.stream_policies(client, site_id)
|> Stream.filter(& &1["enabled"])
|> Enum.to_list()

UnifiApi.Network.Hotspot.stream_vouchers(client, site_id)
|> Stream.reject(& &1["expired"])
|> Enum.map(& &1["code"])

UnifiApi.Network.Resources.stream_dpi_categories(client)
|> Enum.to_list()
```

Stream functions raise on API errors, making them safe to compose in pipelines.

### Available stream functions

Integration API (offset / limit):

| Module | Function |
|--------|----------|
| Sites | `stream/2` |
| Devices | `stream/3`, `stream_pending/2` |
| Clients | `stream/3` |
| Networks | `stream/3` |
| Wifi | `stream/3` |
| Firewall | `stream_zones/3`, `stream_policies/3` |
| Hotspot | `stream_vouchers/3` |
| ACL | `stream/3` |
| DNS | `stream/3` |
| TrafficMatching | `stream/3` |
| Resources | `stream_wans/3`, `stream_vpn_tunnels/3`, `stream_vpn_servers/3`, `stream_radius_profiles/3`, `stream_device_tags/3`, `stream_dpi_categories/2`, `stream_dpi_applications/2`, `stream_countries/2` |

Operational v1 API (`_start` / `_limit`, requires cookie auth):

| Module | Function |
|--------|----------|
| Events | `stream/3` (with `:within_hours`) |
| Alarms | `stream/3` (with `:archived`) |
| IDS | `stream/3` (with `:within_hours`) |

Operational v2 API (`pageSize` / `pageNumber`, requires cookie auth):

| Module | Function |
|--------|----------|
| ClientsHistory | `stream/3` (with `:within_hours`, `:type`, `:search`) |
| SystemLog | `stream/3` |

```elixir
# Stream every event in the last 24 hours, no manual paging
UnifiApi.Network.Events.stream(authed, "default", within_hours: 24)
|> Enum.to_list()

# Top 5 most recent IDS detections
UnifiApi.Network.IDS.stream(authed, "default", within_hours: 1)
|> Enum.take(5)
```

For other v1 endpoints, drop down to `UnifiApi.Client.stream_v1/3`
directly — it takes a path and arbitrary `:params`. For arbitrary
page-numbered v2 endpoints, use `UnifiApi.Client.stream_paged/2`
with a custom `fetch_page` function.

### Manual pagination

If you need per-page control, use `list` with `:offset` and `:limit`:

```elixir
{:ok, page1} = UnifiApi.Network.Devices.list(client, site_id, limit: 50, offset: 0)
{:ok, page2} = UnifiApi.Network.Devices.list(client, site_id, limit: 50, offset: 50)

# Filter (UniFi filter expression syntax)
{:ok, wireless} = UnifiApi.Network.Clients.list(client, site_id,
  filter: "type.eq(WIRELESS)"
)
```

### Filter syntax

Filters use the format `property.function(args)` and can be combined:

| Function | Example |
|----------|---------|
| `eq` | `name.eq(Office)` |
| `ne` | `type.ne(WIRELESS)` |
| `gt`, `ge`, `lt`, `le` | `connectedAt.gt(1700000000)` |
| `in`, `notIn` | `type.in(WIRED,VPN)` |
| `like` | `name.like(cam*)` |
| `isNull`, `isNotNull` | `ipAddress.isNotNull()` |
| `isEmpty` | `name.isEmpty()` |
| `contains`, `containsAny`, `containsAll`, `containsExactly` | `tags.contains(vip)` |

Combine with `and()`, `or()`, `not()`.

## Data Extraction Recipes

Common patterns for pulling structured data out of your UniFi controller.

### Export all clients to a list of maps

```elixir
client = UnifiApi.new()

all_clients =
  UnifiApi.Network.Sites.stream(client)
  |> Enum.flat_map(fn site ->
    UnifiApi.Network.Clients.stream(client, site["id"])
    |> Enum.map(&Map.put(&1, "site", site["name"]))
  end)

# Filter only wireless clients
wireless = Enum.filter(all_clients, &(&1["type"] == "WIRELESS"))
```

### Build a device inventory CSV

```elixir
client = UnifiApi.new()

rows =
  UnifiApi.Network.Sites.stream(client)
  |> Enum.flat_map(fn site ->
    UnifiApi.Network.Devices.stream(client, site["id"])
    |> Enum.map(fn device ->
      [site["name"], device["name"], device["mac"], device["model"], device["state"]]
      |> Enum.join(",")
    end)
  end)

csv = ["site,name,mac,model,state" | rows] |> Enum.join("\n")
File.write!("devices.csv", csv)
```

### Scrape all camera snapshots

```elixir
client = UnifiApi.new()
{:ok, cameras} = UnifiApi.Protect.Cameras.list(client)

for camera <- cameras, camera["state"] == "CONNECTED" do
  case UnifiApi.Protect.Cameras.snapshot(client, camera["id"], high_quality: true) do
    {:ok, jpeg} ->
      name = camera["name"] |> String.replace(~r/[^\w]/, "_")
      File.write!("snapshots/#{name}.jpg", jpeg)

    {:error, reason} ->
      IO.puts("Failed #{camera["name"]}: #{inspect(reason)}")
  end
end
```

### Collect network topology (sites, networks, devices)

```elixir
client = UnifiApi.new()

topology =
  UnifiApi.Network.Sites.stream(client)
  |> Enum.map(fn site ->
    sid = site["id"]

    %{
      site: site["name"],
      networks:
        UnifiApi.Network.Networks.stream(client, sid)
        |> Enum.map(&Map.take(&1, ["id", "name", "vlanId", "subnet"])),
      devices:
        UnifiApi.Network.Devices.stream(client, sid)
        |> Enum.map(&Map.take(&1, ["id", "name", "mac", "model", "state"]))
    }
  end)
```

### Monitor connected client count over time

```elixir
client = UnifiApi.new()
[site | _] = UnifiApi.Network.Sites.stream(client) |> Enum.take(1)

# Poll every 60 seconds
Stream.interval(60_000)
|> Stream.map(fn _ ->
  counts =
    UnifiApi.Network.Clients.stream(client, site["id"])
    |> Enum.group_by(& &1["type"])
    |> Map.new(fn {type, list} -> {type, length(list)} end)

  {DateTime.utc_now(), counts}
end)
|> Stream.each(fn {time, counts} ->
  IO.puts("#{time} | WIRED=#{counts["WIRED"] || 0} WIRELESS=#{counts["WIRELESS"] || 0} VPN=#{counts["VPN"] || 0}")
end)
|> Stream.run()
```

### Export firewall rules

```elixir
client = UnifiApi.new()

UnifiApi.Network.Sites.stream(client)
|> Enum.map(fn site ->
  sid = site["id"]

  %{
    site: site["name"],
    zones:
      UnifiApi.Network.Firewall.stream_zones(client, sid)
      |> Enum.map(&Map.take(&1, ["id", "name", "networkIds"])),
    policies:
      UnifiApi.Network.Firewall.stream_policies(client, sid)
      |> Enum.map(&Map.take(&1, ["id", "name", "enabled", "action", "source", "destination"]))
  }
end)
```

### Export hotspot voucher codes

```elixir
client = UnifiApi.new()
[site | _] = UnifiApi.Network.Sites.stream(client) |> Enum.take(1)

active =
  UnifiApi.Network.Hotspot.stream_vouchers(client, site["id"])
  |> Stream.reject(& &1["expired"])
  |> Enum.map(&Map.take(&1, ["code", "name", "timeLimitMinutes", "expiresAt"]))

# Print as a table
for v <- active do
  IO.puts("#{v["code"]}  #{v["name"]}  #{v["timeLimitMinutes"]}min")
end
```

### Dump all Protect device info

```elixir
client = UnifiApi.new()

{:ok, cameras} = UnifiApi.Protect.Cameras.list(client)
{:ok, sensors} = UnifiApi.Protect.Sensors.list(client)
{:ok, lights} = UnifiApi.Protect.Lights.list(client)
{:ok, chimes} = UnifiApi.Protect.Chimes.list(client)
{:ok, nvr} = UnifiApi.Protect.NVR.get(client)

protect_inventory = %{
  nvr: Map.take(nvr, ["id", "name", "modelKey"]),
  cameras: Enum.map(cameras, &Map.take(&1, ["id", "name", "state", "mac", "modelKey"])),
  sensors: Enum.map(sensors, &Map.take(&1, ["id", "name", "state", "batteryStatus"])),
  lights: Enum.map(lights, &Map.take(&1, ["id", "name", "state", "isLightOn"])),
  chimes: Enum.map(chimes, &Map.take(&1, ["id", "name", "state"]))
}
```

### Dashboard data scraper

Pull everything you need for a custom dashboard in one shot — network overview,
client breakdown, device health, WiFi status, and Protect camera states.

```elixir
client = UnifiApi.new()

# Get controller info
{:ok, info} = UnifiApi.Network.Info.get_info(client)

# Collect per-site data
sites_data =
  UnifiApi.Network.Sites.stream(client)
  |> Enum.map(fn site ->
    sid = site["id"]

    # Clients grouped by type
    clients = UnifiApi.Network.Clients.stream(client, sid) |> Enum.to_list()

    client_breakdown =
      clients
      |> Enum.group_by(& &1["type"])
      |> Map.new(fn {type, list} -> {type, length(list)} end)

    # Devices with health status
    devices =
      UnifiApi.Network.Devices.stream(client, sid)
      |> Enum.map(fn d ->
        %{
          name: d["name"],
          mac: d["mac"],
          model: d["model"],
          state: d["state"],
          ip: d["ip"]
        }
      end)

    connected_devices = Enum.count(devices, & &1.state == "CONNECTED")
    disconnected_devices = Enum.count(devices, & &1.state == "DISCONNECTED")

    # Networks
    networks =
      UnifiApi.Network.Networks.stream(client, sid)
      |> Enum.map(&Map.take(&1, ["id", "name", "vlanId"]))

    # WiFi SSIDs
    ssids =
      UnifiApi.Network.Wifi.stream(client, sid)
      |> Enum.map(&Map.take(&1, ["id", "name", "enabled"]))

    # WANs
    wans =
      UnifiApi.Network.Resources.stream_wans(client, sid)
      |> Enum.map(&Map.take(&1, ["id", "name", "status"]))

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
        connected: connected_devices,
        disconnected: disconnected_devices,
        list: devices
      },
      networks: networks,
      ssids: ssids,
      wans: wans
    }
  end)

# Protect overview
{:ok, cameras} = UnifiApi.Protect.Cameras.list(client)
{:ok, sensors} = UnifiApi.Protect.Sensors.list(client)
{:ok, lights} = UnifiApi.Protect.Lights.list(client)
{:ok, nvr} = UnifiApi.Protect.NVR.get(client)

protect_data = %{
  nvr: Map.take(nvr, ["id", "name", "modelKey"]),
  cameras: %{
    total: length(cameras),
    connected: Enum.count(cameras, & &1["state"] == "CONNECTED"),
    list:
      Enum.map(cameras, fn c ->
        %{
          id: c["id"],
          name: c["name"],
          state: c["state"],
          model: c["modelKey"]
        }
      end)
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

# Full dashboard payload
dashboard = %{
  controller_version: info["applicationVersion"],
  scraped_at: DateTime.utc_now(),
  sites: sites_data,
  protect: protect_data
}

# Write to JSON
File.write!("dashboard.json", JSON.encode!(dashboard))
```

You can run this on an interval to feed a time-series database, or serve it
from a Phoenix endpoint for a live dashboard:

```elixir
# Poll every 30 seconds and write fresh data
Stream.interval(30_000)
|> Stream.each(fn _ ->
  # ... same scraper logic above ...
  File.write!("dashboard.json", JSON.encode!(dashboard))
  IO.puts("[#{DateTime.utc_now()}] Dashboard updated")
end)
|> Stream.run()
```

## Formatted Output

`UnifiApi.Formatter` prints API responses as colored ANSI tables in iex.

### Quick shortcuts

```elixir
{:ok, sites} = UnifiApi.Network.Sites.list(client)
UnifiApi.Formatter.sites(sites)

{:ok, devices} = UnifiApi.Network.Devices.list(client, site_id)
UnifiApi.Formatter.devices(devices)
# State column is color-coded: green=CONNECTED, yellow=CONNECTING, red=DISCONNECTED

{:ok, clients} = UnifiApi.Network.Clients.list(client, site_id)
UnifiApi.Formatter.clients(clients)
# Type column is color-coded: blue=WIRED, magenta=WIRELESS, cyan=VPN

{:ok, cameras} = UnifiApi.Protect.Cameras.list(protect)
UnifiApi.Formatter.cameras(cameras)

{:ok, networks} = UnifiApi.Network.Networks.list(client, site_id)
UnifiApi.Formatter.networks(networks)
```

Operational (v1) shortcuts (use the cookie-auth `authed` from
`UnifiApi.Auth.Cookie.login/4` or `UnifiApi.Auth.Session.client/1`):

```elixir
{:ok, events} = UnifiApi.Network.Events.list(authed, "default", within_hours: 1)
UnifiApi.Formatter.events(events)
# subsystem column is color-coded: magenta=wlan, blue=lan, cyan=wan, red=ips, ...

{:ok, alarms} = UnifiApi.Network.Alarms.list(authed, "default")
UnifiApi.Formatter.alarms(alarms)
# severity column is color-coded: red=critical, yellow=warn, blue=info

{:ok, clients} = UnifiApi.Network.ClientsLive.list(authed, "default")
UnifiApi.Formatter.clients_live(clients)
# signal column buckets RSSI by strength (green ≥ -60, yellow -60..-70, red < -70)
# satisfaction column buckets the 0..100 score (green ≥ 80, yellow ≥ 50, red < 50)

{:ok, anomalies} = UnifiApi.Network.Anomalies.list(authed, "default")
UnifiApi.Formatter.anomalies(anomalies)
```

### Custom tables

```elixir
# Pick any columns
{:ok, devices} = UnifiApi.Network.Devices.list(client, site_id)
UnifiApi.Formatter.table(devices, ["name", "mac", "model", "state", "ip"],
  title: "My Devices",
  colors: %{"state" => :state}
)

# Detail view for a single record
{:ok, nvr} = UnifiApi.Protect.NVR.get(protect)
UnifiApi.Formatter.detail(nvr, title: "NVR Info")
```

### Built-in colour rules

Pass any of these as values in the `:colors` map on `table/3` to
colour a column based on its cell value:

| Rule | Behaviour |
|------|-----------|
| `:state` | `CONNECTED`/`ONLINE` → green, `CONNECTING`/`UPDATING` → yellow, `DISCONNECTED`/`OFFLINE` → red |
| `:type` | `WIRED` → blue, `WIRELESS` → magenta, `VPN` → cyan, `TELEPORT` → yellow |
| `:subsystem` | `wlan` → magenta, `lan` → blue, `wan`/`vpn` → cyan, `ips`/`alarm` → red, `system` → yellow |
| `:severity` | `critical`/`error` → red, `warn`/`warning` → yellow, `info` → blue |
| `:rssi` | numeric dBm: ≥ -60 green, ≥ -70 yellow, else red |
| `:satisfaction` | numeric 0..100: ≥ 80 green, ≥ 50 yellow, else red |

## Error Handling

All functions return `{:ok, body}` on success or `{:error, reason}` on failure.

Every error is one of five exception structs, together forming the
`UnifiApi.Error.t()` umbrella, so an exhaustive `case` is possible:

```elixir
case UnifiApi.Network.Devices.get(client, site_id, "bad-id") do
  {:ok, device} ->
    IO.inspect(device)

  {:error, %UnifiApi.AuthError{reason: :unauthorized}} ->
    IO.puts("Invalid API key")

  {:error, %UnifiApi.AuthError{reason: :forbidden}} ->
    IO.puts("API key lacks permission")

  {:error, %UnifiApi.RateLimitError{retry_after: seconds}} ->
    Process.sleep(seconds * 1000)
    retry()

  {:error, %UnifiApi.ApiError{status: 404}} ->
    IO.puts("Not found")

  {:error, %UnifiApi.ApiError{code: code}} when is_binary(code) ->
    # Legacy v1 endpoints answer 200 with the failure in the body.
    IO.puts("Controller error: #{code}")

  {:error, %UnifiApi.ApiError{status: status, body_preview: preview}} ->
    IO.puts("HTTP #{status}: #{preview}")

  {:error, %UnifiApi.TransportError{reason: reason}} ->
    IO.puts("Transport error: #{inspect(reason)}")
end
```

| Struct | When |
|--------|------|
| `UnifiApi.AuthError` | 401 / 403 |
| `UnifiApi.RateLimitError` | 429, with a parsed and clamped `Retry-After` |
| `UnifiApi.ApiError` | any other non-2xx, **or** a legacy v1 envelope error (HTTP 200 with `code` set) |
| `UnifiApi.TransportError` | no HTTP response at all — refused, DNS, TLS, timeout. The underlying `Req` exception is kept in `:original` |
| `UnifiApi.StreamError` | mid-stream failure, from the `stream/*` functions only |

Raw response bodies are never retained. Each struct carries a
`:body_preview` — scrubbed of URLs and hostnames, truncated to 128
characters — so an error reaching a log or an exception tracker cannot leak
the response (CWE-209 / OWASP A09).

A couple of functions return a documented plain atom for a non-failure
outcome: `Sites.find_by_name/2` gives `{:error, :not_found}` and
`Cookie.logout/2` gives `{:error, :not_logged_in}`.

### Upgrading from a previous version

See [UPGRADING.md](UPGRADING.md) for breaking-change details and concrete
before/after examples. v0.4.0 is a breaking release: the error umbrella
above replaces ten ad-hoc shapes, path prefixes moved onto the client, and
certificate pinning — which never actually worked — is now enforced.

## Multiple Controllers

The library is stateless — every API call takes a `Req.Request.t()` as
its first argument and the request struct holds all the configuration.
Managing multiple controllers is just managing multiple request structs:

```elixir
controllers = %{
  hq:     UnifiApi.new(base_url: "https://10.0.0.1",  api_key: hq_key),
  branch: UnifiApi.new(base_url: "https://10.1.0.1",  api_key: branch_key),
  home:   UnifiApi.new(base_url: "https://192.168.1.1", api_key: home_key)
}

# Pull devices from every controller in parallel
controllers
|> Task.async_stream(fn {name, client} ->
     case UnifiApi.Network.Sites.list(client) do
       {:ok, sites} -> {name, length(sites)}
       {:error, _}  -> {name, :unreachable}
     end
   end,
   max_concurrency: 5,
   timeout: 10_000
)
|> Enum.to_list()
```

If the controllers use different path conventions (UDM vs Cloud Key), say so
per client. Each client carries its own prefixes:

```elixir
defmodule MyApp.Controllers do
  @controllers %{
    hq:
      UnifiApi.new(
        base_url: "https://10.0.0.1",
        api_key: System.fetch_env!("HQ_KEY"),
        style: :udm
      ),
    branch:
      UnifiApi.new(
        base_url: "https://10.1.0.1",
        api_key: System.fetch_env!("BRANCH_KEY"),
        style: :cloud_key
      )
  }

  def call(name, fun), do: fun.(@controllers[name])
end

MyApp.Controllers.call(:branch, fn client ->
  UnifiApi.Network.Sites.list(client)
end)
```

Before v0.4.0 this needed `Application.put_env/3` around every call, which
could not describe two flavours at once and raced any concurrent request.

For long-running pollers that need cookie-authenticated v1 access on
multiple controllers, log in once per controller at startup and reuse
the authenticated request struct — `UnifiApi.Auth.Cookie.refresh_csrf/2`
can refresh the CSRF token without a full re-login.

## Self-Signed Certificates

UDM and Cloud Key controllers ship self-signed TLS certificates by default.
As of **v0.4.0**, `unifi_api` is **secure-by-default**: TLS verification is
on (`verify_ssl: true`) unless you explicitly opt out. This closes CWE-295
/ OWASP A02 — previously the `x-api-key`, session cookie, and (cookie-auth
flow) controller username/password all round-tripped over an unverified
connection, exposing every credential to MITM.

For self-signed controllers you have three options — **pick fingerprint
pinning or a trusted CA, not "no verification"**:

### 1. Fingerprint pinning (recommended for self-signed setups)

```elixir
client = UnifiApi.new(
  base_url: "https://192.168.1.1",
  api_key: "abc",
  cert_fingerprints: ["sha256:AB:CD:EF:..."]
)
```

The TLS handshake is rejected unless the certificate the controller presents
matches one of the configured SHA-256 fingerprints. This pins the connection
to the specific physical device — much stronger than `verify_ssl: false` and
without requiring a CA.

> **Fixed in v0.4.0.** In v0.3.0 this feature did not work and did not
> protect you: the option set was rejected by `:ssl` on every pinned
> connection, and the verification callback accepted *any* self-signed
> certificate regardless of its fingerprint. See
> [UPGRADING.md](UPGRADING.md#security-notice-certificate-pinning).

Pin the certificate the controller cannot prove:

  * **Self-signed controller** (the UniFi default) — pin its own certificate.
    This is the normal case.
  * **Controller behind a private CA** — pin the **CA** certificate. Pinning a
    leaf whose issuer cannot be verified is rejected, because accepting it
    would mean deferring the decision to a callback that may never arrive.
    Installing the CA at the OS level and using `verify_ssl: true` also works.

A pinned certificate is not additionally hostname-checked: a SHA-256 pin
names one exact certificate and is strictly stronger than a name match, and
UniFi controllers are routinely reached by IP with a certificate whose
CN/SAN does not cover it. Trust *inherited* from a pinned CA **is**
hostname-checked.

Get the fingerprint with `openssl`:

```bash
echo | openssl s_client -connect 192.168.1.1:443 2>/dev/null \
  | openssl x509 -fingerprint -sha256 -noout
# => sha256 Fingerprint=AB:CD:EF:...
```

Accepted formats:

```elixir
cert_fingerprints: ["sha256:AB:CD:EF:01:..."]    # ssh-keygen / openssl style
cert_fingerprints: ["AB:CD:EF:01:..."]            # without prefix
cert_fingerprints: ["abcdef01..."]                # plain 64-char hex
cert_fingerprints: ["fp1...", "fp2..."]           # multiple (e.g. cert rotation)
```

### 2. Real CA verification

```elixir
client = UnifiApi.new(verify_ssl: true)  # default as of v0.4.0
```

Use this if you've installed your own CA on the controller and trusted it
at the OS level. The strongest option, and the default behaviour.

### 3. No verification (last-resort escape hatch — insecure)

```elixir
# Per-client opt-out:
client = UnifiApi.new(base_url: "https://192.168.1.1", api_key: "abc", verify_ssl: false)

# Or globally via env var (config/runtime.exs reads this):
#   UNIFI_INSECURE_TLS=1
```

The connection is encrypted but unauthenticated. Anyone on the network path
between you and the controller can intercept traffic — including the
`x-api-key` and cookie-auth credentials — without detection. Fine for a
throwaway script on a trusted LAN; **don't ship this to production**.

## Generating Docs

```bash
mix deps.get
mix docs
open doc/index.html
```

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
