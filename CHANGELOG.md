# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-08-13

> **Upgrading from 0.3.0?** This release is deliberately breaking. See
> [UPGRADING.md](UPGRADING.md) for a step-by-step migration guide with
> before/after examples for every incompatibility below.

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
- `UnifiApi.Client.stream_v1/3` — paginates legacy v1 endpoints via
  `_start` / `_limit`, mirroring `Client.stream/3`. Added
  `stream/3` variants on `UnifiApi.Network.Events`, `Alarms`, and
  `IDS`.
- `UnifiApi.Network.DPI.with_names/2` — joins numeric `cat` / `app`
  IDs against `Resources.list_dpi_categories/1` and
  `list_dpi_applications/1`, populating `category_name` and
  `application_name` on every `by_cat` / `by_app` entry.
- `UnifiApi.Formatter` numeric colour rules `:rssi` (signal-strength
  buckets) and `:satisfaction` (UniFi 0..100 score). Wired into the
  `clients_live/1` shortcut so the `signal` and `satisfaction` columns
  render colour-coded by value.
- CI: the `test` job now runs across three Elixir / OTP combinations
  (`1.18.0` on OTP 26.2.5, `1.18.3` on OTP 27.2, `1.18.4` on OTP 27.2)
  to catch compat regressions across the supported floor.
- `UnifiApi.Client.stream_paged/2` — generic page-number paginator
  (`pageSize` / `pageNumber` style) for endpoints that don't fit the
  integration `offset`/`limit` or v1 `_start`/`_limit` patterns. Used
  by the new v2 streams below.
- `UnifiApi.Network.ClientsHistory.stream/3` and
  `UnifiApi.Network.SystemLog.stream/3` — auto-paginated lazy streams,
  closing the last gaps in the pagination audit.
- `UnifiApi.ping/1` — auth-agnostic `GET /` reachability check.
- `UnifiApi.Time` — `now_ms/0`, `minutes_ago/1`, `hours_ago/1`,
  `days_ago/1` for the unix-millisecond timestamp params used by
  `Protect.Events`, `Network.Traffic`, etc.
- `UnifiApi.Network.Sites.find_by_name/2` and
  `find_by_internal_reference/2` — resolve a site map by human-readable
  name or controller slug without writing
  `Sites.list(client) |> Enum.find(...)` boilerplate.
- README: expanded "Self-Signed Certificates" section covering all three
  TLS modes (`verify_ssl: false`, fingerprint pinning, real CA), with an
  `openssl` recipe for extracting the fingerprint.
- `UnifiApi.ApiError` and `UnifiApi.TransportError` — the two error structs
  that were missing, completing the `UnifiApi.Error.t()` umbrella.
- `UnifiApi.Error` — the umbrella type plus `from_transport/1`.
- `:style` option on `UnifiApi.new/1` (`:udm` | `:cloud_key`) selecting all
  four path prefixes at once, plus per-prefix `:network_path`,
  `:protect_path`, `:v1_path`, `:protect_v1_path` overrides.
- `UnifiApi.Client.prefix/2`, `network_prefix/1`, `protect_prefix/1`,
  `v1_prefix/1`, `protect_v1_prefix/1`, and `style/1` — the client-aware
  replacements for the removed 0-arity prefix functions.
- `:connect_timeout` option on `UnifiApi.new/1` (default 5_000ms), also
  settable with `config :unifi_api, connect_timeout: ms`.
- `:finch` option on `UnifiApi.new/1` accepting the name of a pool you
  started yourself. Mutually exclusive with the TLS and connect-timeout
  options, which then belong on your own pool; combining them raises
  rather than silently dropping your transport settings.
- `opts \\ []` on ten paginated `list/*` — Protect `Chimes`, `Viewers`,
  `Lights`, `Sensors`, `Liveviews` and Network `ActiveLeases`,
  `PortForward`, `PortAnomalies`, `RogueAP`, `UPS`. Validated with
  `Keyword.validate!/2`, so an unknown key raises `ArgumentError`.
- `protect_v1_prefix` in `UnifiApi.detect/1`'s `controller_info`, which
  previously reported only 2 of the 4 prefixes a caller needs. `info.style`
  now feeds straight back into `UnifiApi.new/1`.
- `@type t` on `UnifiApi.StreamError`, clearing the project's only dialyzer
  error (`defexception` never emits one).
- Every resource `stream/*` `@doc` now documents the error contract: the
  enumerable is heterogeneous by default and its last element may be
  `{:error, %UnifiApi.StreamError{}, cursor}`.
- A real-TLS-handshake test harness (`test/support/tls_server.ex` plus
  committed certificate fixtures). The suite previously reached `:ssl`
  nowhere, which is how the pinning defects below shipped.

### Changed

- **Breaking:** the `req` dependency requirement moved from `~> 0.6` to
  `~> 0.7`. Consumers must allow req 0.7 — a locked `~> 0.6` in your own
  `mix.exs` will block resolution. Transitively this bumps the lock from
  req 0.6.3 → 0.7.2, finch 0.21.0 → 0.23.0, mint 1.7.1 → 1.9.3, and
  hpax 1.0.3 → 1.0.4. Run `mix deps.update req` after upgrading.
- **Breaking:** all errors are now one of five structs, `UnifiApi.Error.t()`,
  replacing ten ad-hoc shapes. `{:error, {status, body}}` becomes
  `%UnifiApi.ApiError{}`; `{:error, {:unifi_error, msg}}` becomes
  `%UnifiApi.ApiError{code: msg}`; a bare `%Req.TransportError{}` becomes
  `%UnifiApi.TransportError{}`. Raw response bodies are no longer retained —
  only a scrubbed, truncated `body_preview`.
- **Breaking:** `UnifiApi.detect/1` and `UnifiApi.ping/1` returned different
  shapes for the identical situation and are now reconciled on
  `%UnifiApi.ApiError{}`.
- **Breaking:** `UnifiApi.Client.network_prefix/0`, `protect_prefix/0`,
  `v1_prefix/0` and `protect_v1_prefix/0` are removed in favour of arity-1
  versions taking the client. Prefixes are resolved once in `new/1` and
  carried on the struct, so a UDM client and a Cloud Key client can finally
  coexist in one VM. The `Application` env keys still work.
- **Breaking:** `Network.Events`, `Alarms`, `IDS`, `ClientsHistory` and
  `SystemLog` `stream/3` now honour `:max_pages`, `:max_items` and
  `:raise_errors`, which they previously discarded in silence. Code that
  passed `max_items:` and was ignored will now be capped — correct, but a
  behaviour change. Unknown option keys raise `ArgumentError`.
- **Breaking:** the ten paginated `list/*` are documented as returning the
  first page only; use the matching `stream/*` for full enumeration.
- **Breaking:** `Protect.Cameras.ptz_patrol_start/3`, `ptz_goto/3` and
  `Network.Devices.execute_port_action/5` now guard their integer path
  segments; a non-integer raises `FunctionClauseError`.
- `UnifiApi.Auth.Session.client/1` and `csrf_token/1` are lock-free
  `:persistent_term` reads with no `GenServer.call`. Callers previously
  queued behind a re-login's blocking HTTP round trip.
- `Session.refresh/2` and `relogin/2` take an optional timeout, default
  60_000ms. `refresh/1`'s old 5s default reliably raised `exit(:timeout)`
  while the session process carried on working.
- Concurrent `Session.relogin/1` calls are coalesced: a request carrying a
  timestamp older than the last successful login is answered `:ok` without
  logging in again. On expiry every consumer sees a 401 at once, which used
  to become N sequential full logins.
- Server-dictated retry sleeps are clamped to 300s. `Retry-After: 3600`
  previously parked the calling process for an hour inside what reads as a
  bounded `Req.get/2` — `:receive_timeout` does not cover the retry sleep.
- New internal `UnifiApi.Resource` macro replaces 37 copies of
  `defp prefix`, 20 of `defp maybe_param`, and shortens 115 inline
  `Client.validate_id!/1` calls. Internal, but it is why every resource
  module's diff is large.
- `mix.exs` `package/0` gained a `files:` allow-list, so the tarball no
  longer ships `priv/` (a 4.4 MB dialyzer PLT). It is now ~70 KB.
- The `hex_vet` CI gate fails the build instead of only printing,
  `publish` depends on it, and `mix hex.audit` runs in CI.

### Fixed

- An unparseable `Retry-After` no longer raises; it falls back to the
  bounded default.
- `scrub_body_preview/1` truncates before scrubbing. Producing a 128-char
  preview from an 897 KB body cost ~32ms and ~2.6 MB of garbage on every
  401/403/429; it is now ~24µs.
- `:cert_fingerprints` no longer puts the 162-certificate OS trust store
  into Req's Finch pool key, which Req hashes on **every** request:
  measured 476 KB serialized and ~2.4ms of CPU per request, now 364 bytes
  and ~2µs.
- A CSRF rotation that does not change the token no longer rewrites
  `:persistent_term`. Each write triggers a global scan of every process
  (~169µs with 2000 live processes) and controllers echo the header on
  essentially every response.
- A rotated CSRF token is now published synchronously by the response step
  rather than via a cast, closing a window in which the next request from
  the same process injected the token the controller had just replaced.
- `nil` from `config :unifi_api, verify_ssl: nil` no longer reads as
  "disabled" and silently downgrades TLS to `verify: :verify_none`.

### Security

- **Certificate pinning did not work and did not protect anyone.** Three
  defects, all found by driving a real TLS handshake (CWE-295):
  1. The code set `server_name`, which is not an `:ssl` option. `:ssl`
     forwarded it to `gen_tcp:connect/4`, which raised `:badarg` — so
     **every** pinned connection failed before sending a byte.
  2. The `verify_fun` returned `{:valid, state}` for
     `{:bad_cert, :selfsigned_peer}` unconditionally and only checked the
     fingerprint in the `:valid_peer` clause, which OTP never reaches for a
     self-signed peer. **Any self-signed certificate was accepted whatever
     its fingerprint** — a total bypass of the advertised guarantee.
  3. A custom `verify_fun` replaces OTP's hostname check, so no hostname
     verification was happening either.
  The pin is now the trust anchor, every `:bad_cert` decision consults it
  and fails closed, and hostname verification is enforced for trust
  inherited from a pinned CA. See UPGRADING.md — pinning a leaf behind an
  unknown private CA is now correctly rejected.
- The API key no longer lives in a header on the client struct; a request
  step closing over it injects it at send time. Req's `Inspect` redacts only
  `authorization`, and the client is argument one of every public function,
  so `x-api-key` previously reached every stack frame, `dbg/1` call, crash
  log, and error-tracker breadcrumb (CWE-522 / CWE-209).
- `UnifiApi.Auth.Session` implements `format_status/1`, so `:gen_server`'s
  abnormal-termination log no longer dumps the session cookie, the CSRF
  token, or the plaintext credentials captured by the deprecated
  `:username`/`:password` closure (CWE-209 / CWE-532).
- Three integer path segments were interpolated into request paths without
  validation while sibling id arguments went through `validate_id!/1`. A
  consumer forwarding an HTTP parameter handed an attacker authenticated
  SSRF against the controller's own API (CWE-22 / OWASP A03).

### Removed

- `UnifiApi.Client.network_prefix/0`, `protect_prefix/0`, `v1_prefix/0`,
  `protect_v1_prefix/0` — replaced by the arity-1 forms.
- `lib/unifi_api/application.ex`. A library must not ship an `Application`
  callback; consumers supervise `UnifiApi.Auth.Session` themselves.

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

[0.4.0]: https://github.com/nyo16/unifi_api/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/nyo16/unifi_api/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/nyo16/unifi_api/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nyo16/unifi_api/releases/tag/v0.1.0
