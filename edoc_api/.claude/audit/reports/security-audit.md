# Security Audit: EdocAPI

**Date:** 2026-02-19
**Project:** Edoc API (Elixir/Phoenix)

## Executive Summary

The EdocAPI application demonstrates a **moderate security posture** with several critical vulnerabilities that require immediate attention. The application implements proper authentication using JWT tokens and Argon2 password hashing, and uses Ecto changesets for input validation. However, there are concerning issues including hardcoded secrets in configuration files, potential information disclosure through error messages, and missing security headers.

**Overall Risk Level: MEDIUM-HIGH**

---

## Critical Vulnerabilities

### Hardcoded Secrets in Configuration Files

- **Severity**: Critical
- **Location**:
  - `/home/biba/codes/e-doc/edoc_api/config/config.exs:53`
  - `/home/biba/codes/e-doc/edoc_api/config/dev.exs:27`
  - `/home/biba/codes/e-doc/edoc_api/config/test.exs:20`
- **Issue**: JWT secret and secret_key_base are hardcoded in configuration files
  ```elixir
  # config/config.exs:53
  config :edoc_api, EdocApi.Auth, jwt_secret: "dev-secret-change-me"

  # config/dev.exs:27
  secret_key_base: "uQY/NtqZZR1pps7A4pBUyNzYlU4l0KcpHhc45SNFfsHDSyOQiKI2RSPhCe/IlGdM"

  # config/test.exs:20
  secret_key_base: "zOLb+Q7Bj/xLH8g59iozHbiBpo9pwB88GC69Zbb/DbrTQ+fk6Hzyy14zENsnf6Fu"
  ```
- **Fix**: The production configuration properly loads secrets from environment variables in `runtime.exs`, but the base config files should not contain hardcoded secrets. Use a placeholder or raise an error if secrets are not configured.
- **OWASP**: CWE-798 (Use of Hard-coded Credentials)

### Missing Log Parameter Filtering

- **Severity**: High
- **Location**: `/home/biba/codes/e-doc/edoc_api/config/config.exs`
- **Issue**: No `filter_parameters` configuration to prevent sensitive data from being logged
- **Fix**: Add to config:
  ```elixir
  config :phoenix, :filter_parameters, ["password", "password_hash", "token", "secret"]
  ```
- **OWASP**: CWE-598 (Use of GET Request Method With Sensitive Query Strings)

### Information Disclosure through inspect()

- **Severity**: Medium-High
- **Location**: Multiple error handlers
  - `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/auth_controller.ex:28, 104`
  - `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/buyers_controller.ex:69, 94, 114`
- **Issue**: Using `inspect(reason)` in error responses may leak internal implementation details
  ```elixir
  ErrorMapper.unprocessable(conn, "signup_failed", %{reason: inspect(reason)})
  ```
- **Fix**: Return sanitized error messages without internal details

### Insecure Session Configuration in Development

- **Severity**: Medium
- **Location**: `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/endpoint.ex:7-14`
- **Issue**: Session signing salt is hardcoded and `secure_cookies` defaults to false
  ```elixir
  @session_secure Application.compile_env(:edoc_api, :secure_cookies, false)
  @session_options [
    store: :cookie,
    key: "_edoc_api_key",
    signing_salt: "SYV+DX7i",  # Hardcoded
    same_site: if(@session_secure, do: "Strict", else: "Lax"),
    secure: @session_secure
  ]
  ```
- **Fix**: Load signing_salt from runtime configuration

---

## Authentication

**Status: Good with Minor Issues**

### Positive Findings:
- **Password Hashing**: Uses Argon2 (industry best practice) in `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/accounts/user.ex:36`
  ```elixir
  password -> put_change(changeset, :password_hash, Argon2.hash_pwd_salt(password))
  ```
- **Timing-Safe Authentication**: Implements `Argon2.no_user_verify()` to prevent timing attacks in `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/accounts.ex:22-35`
  ```elixir
  def authenticate_user(email, password) do
    case get_user_by_email(email) do
      nil ->
        Argon2.no_user_verify()  # Prevents timing attacks
        Errors.business_rule(:invalid_credentials, %{email: email})
      # ...
    end
  end
  ```
- **JWT Implementation**: Uses Joken library with proper claims validation in `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/auth/token.ex`

### Issues Found:
- **Token Expiry**: JWT tokens have 7-day expiry (`@ttl_seconds 60 * 60 * 24 * 7`), which may be too long for sensitive applications
- **Email Verification**: Tokens are 32 bytes (256 bits) which is good, using `:crypto.strong_rand_bytes/1`

### Recommendations:
1. Consider shorter JWT expiry with refresh token mechanism
2. Implement token revocation on logout (currently not implemented)

---

## Authorization

**Status: Good - Proper Scoping Implemented**

### Positive Findings:
- **Data Isolation**: All data access is properly scoped by user_id in context functions
  - `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/invoicing.ex:21-24`:
    ```elixir
    def get_invoice_for_user(user_id, invoice_id) do
      Invoice
      |> where([i], i.id == ^invoice_id and i.user_id == ^user_id)
      |> Repo.one()
    ```
  - `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/buyers.ex:35-40`:
    ```elixir
    def get_buyer_for_company(buyer_id, company_id) do
      Buyer
      |> where(id: ^buyer_id, company_id: ^company_id)
      |> Repo.one()
    end
    ```

- **Context Layer Authorization**: Company-based scoping prevents horizontal privilege escalation
- **No Direct Repo Access**: Controllers use context functions that enforce ownership

### Issues Found:
- **Session Authentication Missing Verification Check**: The `AuthenticateSession` plug at `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/plugs/authenticate_session.ex` does not check if the user's email is verified, unlike the JWT authenticate plug

---

## Input Validation

**Status: Excellent - Changesets Used Properly**

### Positive Findings:
- **All User Input Validated**: Changesets used for all user input
  - `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/core/buyer.ex:48-59`
  - `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/core/company.ex:48-58`

- **Custom Validators**: BIN/IIN validation, Email validation
- **Length Constraints**: Proper min/max validation on fields

### Issues Found:
None significant. The application follows best practices for input validation.

---

## OWASP Top 10 Findings

### A01:2021 - Broken Access Control
**Status: Protected**
- Proper scoping prevents horizontal privilege escalation
- No direct ID-based access without ownership checks

### A02:2021 - Cryptographic Failures
**Status: Mixed**
- **Good**: Argon2 for passwords, secure random token generation
- **Bad**: Hardcoded secrets in config files

### A03:2021 - Injection
**Status: Protected**
- **No SQL Injection Found**: All Ecto queries use the `^` operator for parameterization
  - `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/core.ex:51` uses fragments safely with `^` operator
  - No string interpolation in SQL queries detected

### A04:2021 - Insecure Design
**Status: Needs Improvement**
- Rate limiting only applies to auth endpoints (`/v1/auth/signup`, `/v1/auth/login`)
- Other endpoints have no rate limiting

### A05:2021 - Security Misconfiguration
**Status: Multiple Issues**
- Hardcoded secrets (Critical)
- Missing log parameter filtering (High)
- Debug mode may leak stack traces

### A06:2021 - Vulnerable and Outdated Components
**Status: Good**
- Uses up-to-date dependencies (Phoenix 1.7.10, Ecto 3.10)

### A07:2021 - Identification and Authentication Failures
**Status: Good**
- Proper password hashing
- Timing-safe authentication
- Email verification required

### A08:2021 - Software and Data Integrity Failures
**Status: Not Assessed**
- No supply chain audit performed

### A09:2021 - Security Logging and Monitoring Failures
**Status: Partial**
- Request ID tracking implemented
- Missing structured logging for security events
- No `filter_parameters` configuration

### A10:2021 - Server-Side Request Forgery (SSRF)
**Status: Not Applicable**
- No external URL fetching detected in the codebase

---

## XSS Protection

**Status: Generally Protected**

### Positive Findings:
- **Auto-escaping**: HEEX templates auto-escape by default
- **No `raw()` with User Input Found**: The only `raw()` calls are for JSON encoding of server data
  - `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/invoice_html/new.html.heex:246`:
    ```elixir
    const prefillItems = <%= Phoenix.HTML.raw(Jason.encode!(@prefill_items)) %>;
    ```
    This is acceptable as `@prefill_items` is server-generated data, not user input.

### Concerns:
- The `escapeHtml()` function exists in JavaScript but should be verified for all dynamic content

---

## CSRF Protection

**Status: Enabled**

- CSRF protection enabled in browser pipeline: `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/router.ex:22,32`
- CSRF token properly included in forms and htmx requests: `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/components/layouts.ex:17,85`

---

## Security Headers

**Status: Partial**

### Configured Headers (production only):
- `force_ssl: [hsts: true]` - Good
- CSP configured: `"default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://cdn.tailwindcss.com; ..."`
  - **Issue**: `unsafe-inline` for scripts and styles weakens CSP
  - **Issue**: External CDN dependency (Tailwind) for production

### Missing Headers:
- X-Frame-Options
- X-Content-Type-Options: nosniff
- Referrer-Policy

---

## Rate Limiting & DoS Protection

**Status: Limited Implementation**

- Custom rate limiting plug at `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/plugs/rate_limit.ex`
- **Only applied to**: `/v1/auth/signup` and `/v1/auth/login` (limit: 5 requests/minute)
- **Storage**: ETS table (in-memory, resets on restart)
- **Issue**: No rate limiting on protected endpoints or other sensitive operations

---

## Secrets Management

**Status: Poor in Development, Good in Production**

### Issues:
1. Hardcoded JWT secret in `config/config.exs`
2. Hardcoded `secret_key_base` in dev/test configs
3. Hardcoded session signing salt in endpoint
4. No `.gitignore` rule for `config/prod.secret.exs` (though using runtime.exs instead)

### Positive:
- Production properly uses environment variables via `runtime.exs`

---

## Recommendations

### Critical (Fix Immediately):
1. **Remove hardcoded secrets** from config files
   ```elixir
   config :edoc_api, EdocApi.Auth, jwt_secret:
     System.get_env("JWT_SECRET") || raise "JWT_SECRET not set"
   ```

2. **Add parameter filtering** to prevent sensitive data logging
   ```elixir
   config :phoenix, :filter_parameters, ["password", "token", "secret", "csrf"]
   ```

### High Priority:
3. Add `X-Frame-Options`, `X-Content-Type-Options`, and `Referrer-Policy` headers
4. Review and tighten CSP policy - remove `unsafe-inline` where possible
5. Implement rate limiting for all authenticated endpoints
6. Sanitize error messages - remove `inspect(reason)` from user-facing errors

### Medium Priority:
7. Add `http_only: true` to session configuration explicitly
8. Consider shorter JWT token expiry with refresh tokens
9. Remove email from URL redirect in session controller
10. Implement token revocation on logout

### Low Priority:
11. Host Tailwind CSS locally instead of using CDN
12. Add structured security event logging
13. Implement security monitoring/alerting
