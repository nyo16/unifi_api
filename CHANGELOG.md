# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `cert_fingerprints` option on `UnifiApi.new/1` for SHA-256 certificate
  pinning. Set this to a list of fingerprints (`"sha256:AB:CD:..."`,
  `"AB:CD:..."`, or plain 64-char hex) to verify the controller's
  self-signed certificate without disabling TLS validation entirely.
  Overrides `:verify_ssl` when present. Also configurable via
  `config :unifi_api, :cert_fingerprints, [...]`.
- `UnifiApi.Auth.Cookie.login/4` for cookie + CSRF authentication. Use this
  to access endpoints that Ubiquiti has not yet exposed under `x-api-key`
  (events, alarms, IDS, anomalies, historical clients, DPI, topology, …)
  and on Cloud Key controllers without an API key. Supports both
  `:udm` (`/api/auth/login`) and `:cloud_key` (`/api/login`) styles.
  Also exposes `refresh_csrf/2`, `csrf_token/1`, and `logout/2`.
  CSRF rotation is **not** auto-handled in this release — see the module
  docs for trade-offs.
- `UnifiApi.detect/1` probes `GET /` and reports whether the controller is
  UniFi OS (`:udm`) or a standalone / Cloud Key (`:cloud_key`), returning a
  bundle with `network_prefix`, `protect_prefix`, `v1_prefix`, and
  `auth_path`. Heuristic mirrors `unpoller/unpoller`.
- `UnifiApi.Client.v1_prefix/0` and matching `:v1_path` config key
  (default `/proxy/network`, override with `""` for Cloud Key or
  `UNIFI_V1_PATH`) to support the legacy `/api/s/{site}/...` endpoints.
- `UnifiApi.Client.get_v1/3` — generic GET that unwraps the
  `%{"meta" => %{"rc" => "ok"}, "data" => [...]}` envelope used by every
  legacy v1 endpoint, surfacing `meta.rc == "error"` as
  `{:error, {:unifi_error, msg}}`.
- `:params` passthrough on all `Client.{get,post,put,patch,delete}/3`
  for arbitrary query params (used by v1 modules to send `_start`,
  `_limit`, `within`, etc. without polluting the integration-API param
  builder).
- New v1 / v2 endpoint modules (require cookie + CSRF auth). Full Phase 3
  surface, mirroring `unpoller/unpoller`:
  - `UnifiApi.Network.Events` — `/api/s/{site}/stat/event`.
  - `UnifiApi.Network.Alarms` — `/api/s/{site}/list/alarm` plus
    `archive/3`.
  - `UnifiApi.Network.Anomalies` — `/api/s/{site}/stat/anomalies`.
  - `UnifiApi.Network.IDS` — `/api/s/{site}/stat/ips/event`.
  - `UnifiApi.Network.RogueAP` — `/api/s/{site}/stat/rogueap` and
    `/rest/rogueknown`.
  - `UnifiApi.Network.ClientsLive` — `/api/s/{site}/stat/sta` (rich
    wireless stats) plus `list_all/3` for `/stat/alluser`.
  - `UnifiApi.Network.ClientsHistory` —
    `/v2/api/site/{site}/clients/history`.
  - `UnifiApi.Network.DPI` — `/api/s/{site}/stat/sitedpi` and
    `/stat/stadpi`.
  - `UnifiApi.Network.Traffic` — `/v2/api/site/{site}/traffic` and
    `/country-traffic`.
  - `UnifiApi.Network.SystemLog` —
    `/v2/api/site/{site}/system-log/all`.
  - `UnifiApi.Network.ActiveLeases` —
    `/v2/api/site/{site}/active-leases`.
  - `UnifiApi.Network.WAN` — `/wan/enriched-configuration`,
    `/wan/{id}/isp-status`, `/wan/load-balancing`, `/wan-slas`.
  - `UnifiApi.Network.PortAnomalies` —
    `/v2/api/site/{site}/ports/port-anomalies`.
  - `UnifiApi.Network.UPS` — `/api/s/{site}/stat/ups-devices`.
  - `UnifiApi.Network.PortForward` — full CRUD for
    `/api/s/{site}/rest/portforward`.
  - `UnifiApi.Network.Dashboard` —
    `/v2/api/site/{site}/aggregated-dashboard?historySeconds=N`.
  - `UnifiApi.Network.Topology` — `/v2/api/site/{site}/topology`.
  - `UnifiApi.Protect.Events` — `/proxy/protect/api/events`,
    `/api/events/{id}/thumbnail` (binary JPEG), `/api/events/system-logs`.
- `UnifiApi.Formatter` shortcuts for the new modules: `events/1`,
  `alarms/1` (severity-coloured), `clients_live/1`, `anomalies/1`. Plus
  new `:subsystem` and `:severity` colour rules on `table/3`.
- New examples scripts under `examples/`:
  - `operational.exs` — cookie auth + recent events + active alarms
    + worst-RSSI clients, with `UnifiApi.detect/1` controller probe.
  - `protect_events.exs` — pulls Protect motion / smartDetect events
    from the last hour and saves each thumbnail as a JPEG.
- README "Multiple Controllers" section with parallel `Task.async_stream`
  pattern and a per-controller path-config recipe for mixed UDM /
  Cloud Key fleets.
- `UnifiApi.Auth.Session` — supervised GenServer that holds cookie +
  CSRF auth state and auto-rotates the CSRF token from response
  headers. Add it to your supervision tree once and call
  `Session.client/1` to get a `Req.Request` whose request steps pull
  the latest auth state at send time. Closes out the deferred
  auto-refresh story in `UnifiApi.Auth.Cookie`.
- README: expanded "Self-Signed Certificates" section covering all three
  TLS modes (`verify_ssl: false`, fingerprint pinning, real CA), with an
  `openssl` recipe for extracting the fingerprint.

### Notes

- `UnifiApi.Auth.Cookie` and `UnifiApi.detect/1` are unit-tested against
  mocked `Req.Test` plugs but not yet exercised end-to-end against live
  UDM Pro and Cloud Key hardware. Please file an issue with controller
  model and firmware version if you encounter shape mismatches.

## [0.3.0] - 2026-05-02

> **Upgrading from 0.2.x?** See [UPGRADING.md](UPGRADING.md) for a step-by-step
> migration guide with before/after examples and a search-and-replace cheat
> sheet for the breaking change below.

### Added

- Typed errors: `UnifiApi.RateLimitError` (with parsed `Retry-After`) and
  `UnifiApi.AuthError` are now returned for 429, 401, and 403 responses, so
  callers can pattern-match without inspecting the status tuple.
- Runnable example scripts under `examples/` (`quickstart.exs`,
  `dashboard.exs`, `snapshots.exs`).
- `CHANGELOG.md` is now bundled in the generated docs.
- README: status badges, "Self-signed certificates" section, expanded error
  handling docs with the new typed errors and a 0.2.x → 0.3.0 migration note.
- `UnifiApi.Network.Devices` `@moduledoc` now documents response fields and
  the shape returned by `get_statistics/3`.

### Changed

- **Breaking:** 401, 403, and 429 responses now return exception structs
  (`%UnifiApi.AuthError{}` / `%UnifiApi.RateLimitError{}`) instead of
  `{:error, {status, body}}` tuples. The motivation is twofold: pattern
  matching on specific HTTP status numbers leaks transport-level concerns
  into caller code, and the parsed `Retry-After` (clamped 1..300s) lets
  pollers back off correctly without re-parsing the response. Callers
  matching `{:error, {401, _}}`, `{:error, {403, _}}`, or `{:error, {429, _}}`
  must update to match the new structs — see [UPGRADING.md](UPGRADING.md).
  Other non-2xx responses still return `{:error, {status, body}}`. Catch-all
  `{:error, _}` matches are unaffected.
- `mix.exs` package metadata: added `maintainers`, `Changelog` and `Upgrading`
  links, and bundled `CHANGELOG.md` + `UPGRADING.md` in `docs.extras`.

## [0.2.0] - 2026-04-30

### Added

- Stream-based auto-pagination via `Stream.resource/3` for every list endpoint
  (`UnifiApi.Network.Devices.stream/3`, `Clients.stream/3`, etc.).
- ANSI formatter (`UnifiApi.Formatter`) for printing API responses as colored
  tables in IEx, with shortcuts for devices/clients/cameras/networks/sites.
- UDM proxy path support: `Client.network_prefix/0` and
  `Client.protect_prefix/0` default to `/proxy/network/integration` and
  `/proxy/protect/integration`; override with `network_path` /
  `protect_path` config (or `UNIFI_NETWORK_PATH` / `UNIFI_PROTECT_PATH` env).
- Comprehensive dashboard data scraper recipe in the README.
- CI/CD pipeline: format check, Credo strict, Dialyzer, ExUnit on Elixir
  1.18.3 / OTP 27.2, automated Hex publish on tags.
- Full `@spec` coverage and `@moduledoc` / `@doc` for every public function.

### Changed

- Bumped Elixir requirement to `~> 1.18`.
- Replaced `Jason` with the Elixir 1.18 stdlib `JSON` module.
- Formatter now correctly handles wrapped (`%{"data" => [...]}`) responses.

## [0.1.0]

### Added

- Initial implementation of the UniFi Network and Protect API client over
  Req, with API-key authentication and the core Network (Sites, Devices,
  Clients, Networks, Wifi, Firewall, Hotspot, ACL, DNS, TrafficMatching,
  Resources) and Protect (Cameras, NVR, Sensors, Lights, Chimes, Viewers,
  Liveviews) modules.

[Unreleased]: https://github.com/nyo16/unifi_api/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/nyo16/unifi_api/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/nyo16/unifi_api/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nyo16/unifi_api/releases/tag/v0.1.0
