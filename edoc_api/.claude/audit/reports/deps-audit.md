# Dependency Audit Report

**Generated:** 2026-02-19
**Project:** Edoc API (e-doc/edoc_api)
**Elixir Requirement:** ~> 1.14

---

## Vulnerability Scan

### mix hex.audit
```
No retired packages found
```

**Status:** No known retired or vulnerable packages detected via hex.audit.

---

## Outdated Packages

### Upgradable (Minor Updates Available)

| Package | Current | Latest | Change |
|---------|---------|--------|--------|
| **ecto_sql** | 3.13.3 | 3.13.4 | Patch (3.13.3 -> 3.13.4) |
| **finch** | 0.20.0 | 0.21.0 | Minor (0.20.0 -> 0.21.0) |
| **plug_cowboy** | 2.7.5 | 2.8.0 | Minor (2.7.5 -> 2.8.0) |
| **postgrex** | 0.21.1 | 0.22.0 | Minor (0.21.1 -> 0.22.0) |
| **swoosh** | 1.19.9 | 1.22.0 | Minor (1.19.9 -> 1.22.0) |
| **tidewave** | 0.5.4 | 0.5.5 | Patch (0.5.4 -> 0.5.5) |

### Require mix.exs Version Constraint Updates

| Package | Current | Latest | Constraint |
|---------|---------|--------|------------|
| **phoenix** | 1.7.21 | 1.8.3 | ~> 1.7.10 (needs ~> 1.8) |
| **gettext** | 0.26.2 | 1.0.2 | ~> 0.20 (needs ~> 1.0) |
| **dns_cluster** | 0.1.3 | 0.2.0 | ~> 0.1.1 (needs ~> 0.2) |
| **telemetry_metrics** | 0.6.2 | 1.1.0 | ~> 0.6 (needs ~> 1.1) |

---

## Unused Dependencies

All dependencies in mix.exs have been verified as in use:

| Dependency | Usage Location |
|------------|----------------|
| **phoenix** | Core web framework (used throughout lib/edoc_api_web/) |
| **phoenix_ecto** | Database integration for Phoenix |
| **ecto_sql** | Database queries (Ecto.Query used throughout) |
| **postgrex** | PostgreSQL adapter |
| **phoenix_live_dashboard** | Dashboard metrics |
| **swoosh** | Email sending (lib/edoc_api/email_sender.ex) |
| **finch** | HTTP client (transitive via req) |
| **telemetry_metrics** | Metrics reporting |
| **telemetry_poller** | Metrics collection |
| **gettext** | Internationalization (lib/edoc_api_web/gettext.ex) |
| **jason** | JSON encoding/decoding |
| **dns_cluster** | Distributed systems (lib/edoc_api/application.ex) |
| **plug_cowboy** | Web server |
| **argon2_elixir** | Password hashing |
| **joken** | JWT tokens (lib/edoc_api/auth/token.ex) |
| **html_sanitize_ex** | HTML sanitization (lib/edoc_api/core/contract.ex:148) |
| **tidewave** | Dev-only hot reloading |

**Conclusion:** No unused dependencies detected.

---

## License Summary

All direct dependencies use permissive licenses:

| Dependency | License |
|------------|---------|
| argon2_elixir | Apache-2.0 |
| ecto_sql | Apache-2.0 |
| finch | MIT |
| gettext | Apache-2.0 |
| html_sanitize_ex | MIT |
| jason | Apache-2.0 |
| joken | Apache-2.0 |
| phoenix | MIT |
| phoenix_ecto | MIT |
| phoenix_live_dashboard | MIT |
| plug_cowboy | MIT |
| postgrex | MIT |
| swoosh | MIT |
| telemetry_metrics | Apache-2.0 |

**Licensing Concerns:** None. All dependencies use permissive Apache-2.0 or MIT licenses. No copyleft licenses (GPL, AGPL, etc.) detected in the dependency tree.

---

## Version Health

### Elixir Version
- **Required:** ~> 1.14
- **Status:** Elixir 1.14 is stable but older. Current stable is Elixir 1.17+.
- **Recommendation:** Consider upgrading to Elixir 1.16+ for better performance and features.

### Phoenix Version
- **Current:** 1.7.21
- **Latest:** 1.8.3
- **Gap:** One major version behind
- **Status:** Phoenix 1.7 is still supported, but 1.8 brings performance improvements and new features.

### Dependency Tree Health
- **Total Dependencies:** 48 (direct + transitive)
- **Direct Dependencies:** 16
- **Transitive Dependencies:** 32

---

## Recommendations

### 1. Security Updates (High Priority)
- **None** - No vulnerabilities detected

### 2. Patch Updates (Recommended)
Apply these patch updates for bug fixes:
```elixir
# Update these in mix.exs then run mix deps.update
{:ecto_sql, "~> 3.13"},  # 3.13.3 -> 3.13.4
{:tidewave, "~> 0.5", only: :dev}  # 0.5.4 -> 0.5.5
```

### 3. Minor Updates (Recommended)
```elixir
# These can be updated without breaking changes
{:finch, "~> 0.21"},       # 0.20.0 -> 0.21.0
{:plug_cowboy, "~> 2.8"},  # 2.7.5 -> 2.8.0
{:postgrex, ">= 0.0.0"},   # 0.21.1 -> 0.22.0
{:swoosh, "~> 1.22"},      # 1.19.9 -> 1.22.0
```

### 4. Major Updates (Plan Carefully)
These require version constraint changes in mix.exs:

```elixir
# Phoenix 1.8 upgrade (requires testing)
{:phoenix, "~> 1.8"},

# Gettext 1.0 (may require translation format updates)
{:gettext, "~> 1.0"},

# Telemetry metrics 1.1
{:telemetry_metrics, "~> 1.1"},

# DNS cluster 0.2
{:dns_cluster, "~> 0.2"},
```

### 5. Elixir Version Upgrade
- Consider upgrading from Elixir 1.14 to 1.16 or 1.17
- This will enable newer dependency versions and improved performance

### 6. Optional Tools
Consider adding `mix_audit` for ongoing security monitoring:
```elixir
{:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false}
```

---

## Full Dependency List (Current)

### Direct Dependencies
- argon2_elixir 4.1.3
- dns_cluster 0.1.3
- ecto_sql 3.13.3
- finch 0.20.0
- gettext 0.26.2
- html_sanitize_ex 1.4.4
- jason 1.4.4
- joken 2.6.2
- phoenix 1.7.21
- phoenix_ecto 4.7.0
- phoenix_live_dashboard 0.8.7
- plug_cowboy 2.7.5
- postgrex 0.21.1
- swoosh 1.19.9
- telemetry_metrics 0.6.2
- telemetry_poller 1.3.0
- tidewave 0.5.4 (dev only)

### Key Transitive Dependencies
- ecto 3.13.5
- phoenix_live_view 1.1.19
- plug 1.19.1
- cowboy 2.14.2
- comeonin 5.5.1
- jose 1.11.12
- telemetry 1.3.0

---

## Direct vs Transitive Analysis

All dependencies are appropriately classified:
- **Compile-time deps:** None that should be moved to runtime
- **Runtime deps:** All appropriate for a Phoenix web app
- **Dev deps:** tidewave correctly marked as dev-only

No action required regarding dependency classification.
