# Upgrading

A guide for users of `unifi_api` upgrading between versions. Each section
covers one release boundary — read only the section(s) that apply to the
versions you're moving across.

For the full release history, see [CHANGELOG.md](CHANGELOG.md).

## v0.3.0 → v0.4.0

**Released:** 2026-08-13

This release is deliberately breaking. It closes an error contract that had
drifted into ten different shapes, moves path configuration off global
application state, and fixes a certificate-pinning implementation that never
worked.

### Summary of breaking changes

| Area | What changed | Severity |
|------|--------------|----------|
| `req` requirement | Now `~> 0.7` (was `~> 0.6`). | Breaking — a `~> 0.6` lock in your own `mix.exs` blocks resolution. |
| Non-2xx responses | `{:error, {status, body}}` → `%UnifiApi.ApiError{}`. The raw body is gone; only a scrubbed `body_preview` remains. | Breaking — pattern-matched callers must update. |
| v1 envelope errors | `{:error, {:unifi_error, msg}}` → `%UnifiApi.ApiError{status: 200, code: msg}`. | Breaking — same. |
| Transport failures | A bare `%Req.TransportError{}` → `%UnifiApi.TransportError{}`, original preserved in `:original`. | Breaking — same. |
| `detect/1` | `{:error, {:unexpected_status, status, body}}` → `%UnifiApi.ApiError{}`, reconciling it with `ping/1`. | Breaking — same. |
| Prefix functions | `Client.network_prefix/0` and friends removed; use the arity-1 forms taking the client. | Breaking — direct callers must update. |
| Stream options | `Network.Events`/`Alarms`/`IDS`/`ClientsHistory`/`SystemLog` `stream/3` now honour `:max_pages`, `:max_items`, `:raise_errors`. | Behaviour change — previously silently discarded. |
| Paginated `list/*` | Ten functions gained `opts \\ []` and are documented as first-page-only; unknown keys raise. | Additive, but the truncation is now explicit. |
| Integer path segments | `Cameras.ptz_patrol_start/3`, `ptz_goto/3`, `Devices.execute_port_action/5` guard their integer arguments. | Breaking — a string argument now raises `FunctionClauseError`. |
| Certificate pinning | Was completely non-functional and insecure; now enforced. | **Security** — read the notice below. |

### Security notice: certificate pinning

If you relied on `:cert_fingerprints` in 0.3.0, **you were not protected**.
Driving a real TLS handshake against the shipped code found three defects:

1. The options set `server_name`, which is not an `:ssl` option at all. `:ssl`
   forwarded it to `gen_tcp:connect/4`, which raised `:badarg` — so every
   pinned connection failed before sending a byte. Nobody could have had a
   working pinned client.
2. The verify function accepted `{:bad_cert, :selfsigned_peer}`
   unconditionally and only compared fingerprints in a later callback that
   OTP never reaches for a self-signed peer. **Any** self-signed certificate
   was accepted regardless of its fingerprint.
3. A custom verify function replaces OTP's hostname check, so hostnames were
   not being verified either.

All three are fixed: the pinned fingerprint is the trust anchor, every
certificate decision consults it and fails closed, and hostname verification
is enforced for trust inherited from a pinned CA.

**One consequence to be aware of.** Pinning is now about the certificate the
controller cannot prove:

  * A self-signed controller (the UniFi default) — pin its own certificate.
    This is the normal case and needs no change.
  * A controller behind a private CA — pin the **CA** certificate, not the
    leaf. Pinning a leaf whose issuer cannot be verified is rejected, because
    accepting it would require deferring the decision to a callback that may
    never arrive, which is exactly the hole that made defect 2 exploitable.
    Alternatively install the CA in the OS trust store and use
    `verify_ssl: true`.

### Migration

#### 1. Allow req 0.7

If your own `mix.exs` constrains req, widen it, then:

```bash
mix deps.update req
```

#### 2. Rewrite non-2xx error matches

Find them:

```bash
grep -rE '\{:error, \{[0-9]{3}' lib/ test/
grep -rn ':unifi_error\|:unexpected_status\|Req.TransportError' lib/ test/
```

**Before (0.3.0):**

```elixir
case UnifiApi.Network.Networks.create(client, site_id, params) do
  {:ok, network} -> {:ok, network}
  {:error, {409, body}} -> {:conflict, body["message"]}
  {:error, {status, _body}} when status >= 500 -> :controller_fault
  {:error, {:unifi_error, "api.err.LoginRequired"}} -> :session_expired
  {:error, %Req.TransportError{reason: :econnrefused}} -> :controller_down
end
```

**After (0.4.0):**

```elixir
case UnifiApi.Network.Networks.create(client, site_id, params) do
  {:ok, network} -> {:ok, network}
  {:error, %UnifiApi.ApiError{status: 409, body_preview: preview}} -> {:conflict, preview}
  {:error, %UnifiApi.ApiError{status: status}} when status >= 500 -> :controller_fault
  {:error, %UnifiApi.ApiError{code: "api.err.LoginRequired"}} -> :session_expired
  {:error, %UnifiApi.TransportError{reason: :econnrefused}} -> :controller_down
end
```

Three things to note:

  * **The raw body is gone.** `%ApiError{}` carries `body_preview` — scrubbed
    of URLs and hostnames and truncated to 128 characters (CWE-209). Code that
    read structured fields out of an error body must instead not rely on it, or
    use `UnifiApi.Client.raw_get/3` and inspect the response itself.
  * **`:status` and `:code` are different axes.** An HTTP failure sets
    `:status` and leaves `:code` `nil`. A legacy v1 envelope error arrives with
    HTTP 200 and sets `:code` to the controller's error string.
  * **`%UnifiApi.TransportError{}` keeps the original** in `:original`, so
    `error.original` is the `%Req.TransportError{}` you used to match on.

Every error is now one of five structs, so an exhaustive `case` is finally
possible:

```elixir
case UnifiApi.Network.Clients.list(client, site_id) do
  {:ok, clients} -> {:ok, clients}
  {:error, %UnifiApi.AuthError{}} -> :reauth
  {:error, %UnifiApi.RateLimitError{retry_after: s}} -> {:backoff, s}
  {:error, %UnifiApi.ApiError{status: status}} -> {:api, status}
  {:error, %UnifiApi.TransportError{reason: reason}} -> {:transport, reason}
end
```

Two functions still return a plain atom for a non-failure outcome, named in
their own `@spec`s: `Sites.find_by_name/2` returns `{:error, :not_found}` and
`Cookie.logout/2` returns `{:error, :not_logged_in}`.

#### 3. Move path prefixes onto the client

The 0-arity prefix functions are gone.

**Before (0.3.0):**

```elixir
path = "#{UnifiApi.Client.network_prefix()}/v1/sites"
```

**After (0.4.0):**

```elixir
path = "#{UnifiApi.Client.network_prefix(client)}/v1/sites"
```

Cloud Key users configured prefixes globally. That still works, but naming the
style is clearer and no longer global:

**Before (0.3.0):**

```elixir
config :unifi_api,
  network_path: "/integration",
  protect_path: "/integration",
  v1_path: ""
```

**After (0.4.0):**

```elixir
client = UnifiApi.new(base_url: url, api_key: key, style: :cloud_key)
```

This is the reason for the change — two controller flavours in one VM was
previously impossible, and any runtime `Application.put_env/3` raced every
in-flight request:

```elixir
udm = UnifiApi.new(base_url: udm_url, api_key: k1, style: :udm)
cloud_key = UnifiApi.new(base_url: ck_url, api_key: k2, style: :cloud_key)
```

Resolution order is: an explicit `network_path:`/`protect_path:`/`v1_path:`/
`protect_v1_path:` option, then the `:style` preset, then the legacy
`Application` env key, then the `:udm` default.

#### 4. Simplify the `detect/1` recipe

`detect/1` used to report only 2 of the 4 prefixes a caller needs, so applying
its output left `protect_v1_prefix` wrong.

**Before (0.3.0):**

```elixir
{:ok, info} = UnifiApi.detect(UnifiApi.new(base_url: url))
Application.put_env(:unifi_api, :network_path, info.network_prefix)
Application.put_env(:unifi_api, :protect_path, info.protect_prefix)
```

**After (0.4.0):**

```elixir
{:ok, info} = UnifiApi.detect(UnifiApi.new(base_url: url))
client = UnifiApi.new(base_url: url, api_key: key, style: info.style)
```

#### 5. Check callers that passed stream options

`Network.Events`, `Alarms`, `IDS`, `ClientsHistory` and `SystemLog`
`stream/3` accepted `:max_pages`, `:max_items` and `:raise_errors` and then
**discarded them**. Same option names as `Client.stream/3`, opposite
behaviour, no error.

```elixir
# In 0.3.0 this paged the ENTIRE event log. In 0.4.0 it stops at 100 items.
UnifiApi.Network.Events.stream(authed, "default", max_items: 100)
```

That is the behaviour the option always claimed, but if you had worked around
the bug by post-filtering, previously-complete results are now truncated on
purpose. Unknown option keys raise `ArgumentError` instead of being ignored.

#### 6. Handle the stream error tail

This has been the contract since 0.4.0's stream rework, and it is now
documented on every resource `stream/*`. A mid-stream error does not raise by
default: the stream halts and yields `{:error, %UnifiApi.StreamError{}, cursor}`
as its **final element**, so the enumerable is heterogeneous.

**Crashes on a transient 500:**

```elixir
UnifiApi.Network.Devices.stream(client, site_id)
|> Enum.map(& &1["name"])
```

**Handle the tail:**

```elixir
items = UnifiApi.Network.Devices.stream(client, site_id) |> Enum.to_list()

case List.last(items) do
  {:error, error, cursor} -> {:error, error, cursor}
  _ -> {:ok, Enum.map(items, & &1["name"])}
end
```

**Or opt back into raising:**

```elixir
UnifiApi.Network.Devices.stream(client, site_id, raise_errors: true)
|> Enum.map(& &1["name"])
```

#### 7. Paginated `list/*` are first-page-only

Ten functions — Protect `Chimes`, `Viewers`, `Lights`, `Sensors`, `Liveviews`
and Network `ActiveLeases`, `PortForward`, `PortAnomalies`, `RogueAP`, `UPS` —
silently returned one page with no count, cursor, or "there is more" signal.
They now take options and say so in their docs. Use the matching `stream/*`
where one exists:

```elixir
# First page only
{:ok, chimes} = UnifiApi.Protect.Chimes.list(client, limit: 50)

# Everything
UnifiApi.Protect.Chimes.stream(client) |> Enum.to_list()
```

#### 8. Integer path arguments must be integers

```elixir
# 0.3.0: interpolated raw into the request path
# 0.4.0: raises FunctionClauseError
UnifiApi.Protect.Cameras.ptz_goto(client, "cam-1", params["slot"])
```

Cast at your boundary: `String.to_integer/1`. These three arguments were the
library's remaining authenticated-SSRF surface, so the guard is intentional.

#### 9. Optional: session call timeouts

`Session.refresh/1` and `relogin/1` still work unchanged. Both now accept an
optional timeout (default 60_000ms); `refresh/1`'s old 5s default reliably
raised `exit(:timeout)` while the session process kept running. If you raised
`:receive_timeout` on your client, pass a matching timeout:

```elixir
UnifiApi.Auth.Session.refresh(MyApp.UnifiSession, 120_000)
```

### Nothing to do if you only care about these

These changes need no action on your side:

  * The API key is no longer rendered by `inspect(client)`, so it no longer
    reaches stack frames, `dbg/1` output, crash logs, or error-tracker
    breadcrumbs.
  * `UnifiApi.Auth.Session`'s crash log no longer contains the session cookie,
    CSRF token, or plaintext credentials.
  * `:cert_fingerprints` clients no longer pay ~2.4ms of CPU per request
    hashing the OS trust store into Req's Finch pool key.
  * Error previews are built ~1300× faster on large bodies.
  * Unchanged CSRF tokens no longer trigger a global `:persistent_term` scan.
  * `Session.client/1` and `csrf_token/1` no longer round-trip the GenServer,
    so they no longer block behind an in-flight re-login.
  * The Hex tarball no longer ships a 4.4 MB dialyzer PLT.
  * `lib/unifi_api/application.ex` is gone; a library must not ship an
    `Application` callback. If you were relying on `:unifi_api` starting a
    supervision tree, supervise `UnifiApi.Auth.Session` yourself.

## v0.2.x → v0.3.0

**Released:** 2026-05-02

### Summary of breaking changes

| Area | What changed | Severity |
|------|--------------|----------|
| 401 / 403 responses | Now return `%UnifiApi.AuthError{}` instead of `{:error, {401, body}}` / `{:error, {403, body}}`. | Breaking — pattern-matched callers must update. |
| 429 responses | Now return `%UnifiApi.RateLimitError{retry_after: seconds, ...}` (with parsed `Retry-After`) instead of `{:error, {429, body}}`. | Breaking — same as above. |

Other status codes (404, 500, etc.) and transport errors are **unchanged**.

### Why

Three reasons:

1. **Pattern matching on `{:error, {401, _}}` couples callers to HTTP status
   numbers.** Auth and rate-limit failures are semantically distinct from a
   generic non-2xx response and deserve their own shapes.
2. **`Retry-After` was previously invisible.** With the old tuple shape,
   callers had to either re-parse the response body or give up on rate-limit
   backoff entirely. The new struct surfaces a clamped, parsed integer so
   pollers can `Process.sleep(seconds * 1000)` directly.
3. **Aligns with Elixir conventions.** Exception structs are how Plug, Phoenix,
   Ecto, Req, and Tesla all signal these conditions.

### Migration

#### 1. Find every `{401, _}`, `{403, _}`, `{429, _}` pattern in your code

A grep over your codebase will find them:

```bash
grep -rE '\{:error, \{4(01|03|29)' lib/ test/
```

#### 2. Rewrite the matches

**Before (0.2.x):**

```elixir
case UnifiApi.Network.Sites.list(client) do
  {:ok, sites} ->
    sites

  {:error, {401, _body}} ->
    raise "API key invalid"

  {:error, {403, _body}} ->
    raise "API key lacks permission"

  {:error, {429, _body}} ->
    Process.sleep(60_000)
    retry()

  {:error, reason} ->
    raise "request failed: #{inspect(reason)}"
end
```

**After (0.3.0):**

```elixir
case UnifiApi.Network.Sites.list(client) do
  {:ok, sites} ->
    sites

  {:error, %UnifiApi.AuthError{reason: :unauthorized}} ->
    raise "API key invalid"

  {:error, %UnifiApi.AuthError{reason: :forbidden}} ->
    raise "API key lacks permission"

  {:error, %UnifiApi.RateLimitError{retry_after: seconds}} ->
    Process.sleep(seconds * 1000)
    retry()

  {:error, reason} ->
    raise "request failed: #{inspect(reason)}"
end
```

Note `retry_after` comes from the `Retry-After` response header (parsed as
seconds or HTTP-date) and is clamped to the range 1..300 seconds. If the
header is missing or unparseable it defaults to 60.

#### 3. If you don't care about these errors, no action is needed

Code that only matches `{:ok, _}` or uses a catch-all `{:error, _}` continues
to work unchanged:

```elixir
case UnifiApi.Network.Sites.list(client) do
  {:ok, sites} -> sites
  {:error, _} -> []
end
```

The new error structs are still `{:error, _}` tuples — only the inner term
changed.

### Supporting both 0.2 and 0.3 in a downstream library

If you maintain a library that wraps `unifi_api` and needs to support both
versions during a deprecation window, match both shapes:

```elixir
case UnifiApi.Network.Sites.list(client) do
  {:ok, sites} ->
    {:ok, sites}

  # 0.3+
  {:error, %UnifiApi.AuthError{}} ->
    {:error, :unauthorized}

  {:error, %UnifiApi.RateLimitError{retry_after: s}} ->
    {:error, {:rate_limited, s}}

  # 0.2.x fallback — remove once you bump unifi_api to ~> 0.3
  {:error, {status, _}} when status in [401, 403] ->
    {:error, :unauthorized}

  {:error, {429, _}} ->
    {:error, {:rate_limited, 60}}

  {:error, reason} ->
    {:error, reason}
end
```

### Reference: error struct shapes

```elixir
%UnifiApi.AuthError{
  status: 401 | 403,
  reason: :unauthorized | :forbidden,
  body: term()
}

%UnifiApi.RateLimitError{
  status: 429,
  retry_after: 1..300,
  body: term()
}
```

Both implement `Exception`, so `Exception.message/1` and `raise` work as
expected.
