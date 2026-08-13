# hex_vet.exs — Security version ledger for unifi_api
#
# Records the minimum acceptable Hex package versions for direct and
# transitive deps that have shipped security advisories. CI verifies
# that every entry here is present in `mix.lock` at or above the floor
# declared below (see `.github/workflows/ci.yml` `hex_vet` job).
#
# The check is FAIL-BLOCKING as of v0.4.0: a lock entry below its floor,
# or a ledger entry that has vanished from `mix.lock`, halts CI with a
# non-zero exit. A vanished entry is a failure on purpose — it means the
# ledger has gone stale (dep dropped or renamed) and needs a re-vet,
# which must be a deliberate edit here rather than a silent pass.
#
# Format: `{package_name_atom, ">= floor_version"}`. The check passes
# iff `mix.lock` pins the package at a version `>= floor_version`.
# This file is plain Elixir data — no Mix, no functions, no aliases —
# because the CI gate reads it with `Code.eval_file/1` under bare
# `elixir -e`, with no project loaded.
#
# Source: `/phx-deps-audit` triage (`deps-audit.md`) — 11 CVEs across
# mint ×3, hpax ×1, req ×2, plug ×2 (+transitives finch/plug_crypto).
#
# Re-vetted for v0.4.0 against the post-`req 0.7` lock. Versions and
# outer (registry) checksums as recorded in `mix.lock`:
#
#   req     0.7.2    c9cdfa276b05d8db2a27fda5d233e6858b764d47189d76cbb186e130a871ae0b
#   finch   0.23.0   80e58d3f936f57e3fdf404f83a3642897ae6d9fb642934e46da4d8fe761b99d5
#   mint    1.9.3    5f7c9342480c069dbbc4eeac3490303c9e01870ff01a7f1d29b6107054fc1e74
#   hpax    1.0.4    afc7cb142ebcc2d01ce7816190b98ce5dd49e799111b24249f3443d730f377ca
#
# The floors below are raised to those vetted versions, so a downgrade
# to a version that predates this audit fails the gate.

[
  {:req, ">= 0.7.2"},
  {:mint, ">= 1.9.3"},
  {:hpax, ">= 1.0.4"},
  {:plug, ">= 1.20.3"},
  {:finch, ">= 0.23.0"},
  {:plug_crypto, ">= 2.2.0"}
]
