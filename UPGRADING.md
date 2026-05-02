# Upgrading

A guide for users of `unifi_api` upgrading between versions. Each section
covers one release boundary — read only the section(s) that apply to the
versions you're moving across.

For the full release history, see [CHANGELOG.md](CHANGELOG.md).

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
