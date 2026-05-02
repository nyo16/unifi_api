# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
