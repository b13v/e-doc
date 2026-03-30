# Security and API Audit Report
**Date:** 2026-02-17
**Project:** e-doc API (Phoenix/Elixir)
**Scope:** Security vulnerabilities and API design improvements

---

## Executive Summary

This audit identified **15 security concerns** and **12 API improvement opportunities** across the codebase. The application demonstrates good security practices in several areas (password hashing with Argon2, JWT authentication, SQL injection protection via Ecto) but has several areas requiring attention.

### Critical Issues: 1
### High Priority: 4
### Medium Priority: 10
### Low Priority: 12

---

## Security Findings

### 1. [CRITICAL] Hardcoded Signing Salt in Session Configuration

**Location:** `lib/edoc_api_web/endpoint.ex:11`

```elixir
@session_options [
  store: :cookie,
  key: "_edoc_api_key",
  signing_salt: "SYV+DX7i",  # HARDCODED - SHOULD BE ENV VAR
  same_site: if(@session_secure, do: "Strict", else: "Lax"),
  secure: @session_secure
]
```

**Risk:** Session cookies can be forged if the signing salt is compromised. This value is hardcoded in source code and likely checked into version control.

**Recommendation:**
```elixir
signing_salt: Application.fetch_env!(:edoc_api, :signing_salt)
```

Add to `config/runtime.exs`:
```elixir
signing_salt =
  System.get_env("SIGNING_SALT") ||
    raise "environment variable SIGNING_SALT is missing"

config :edoc_api, :signing_salt, signing_salt
```

---

### 2. [HIGH] Insufficient Rate Limiting Scope

**Location:** `lib/edoc_api_web/plugs/rate_limit.ex:13-14`

```elixir
def call(conn, opts) do
  ensure_table!()

  limit = Keyword.get(opts, :limit, 5)
  window_seconds = Keyword.get(opts, :window_seconds, 60)
  action = Keyword.get(opts, :action, conn.request_path)
```

**Issues:**
1. Rate limit of 5 requests per minute is ONLY applied to `/auth/signup` and `/auth/login`
2. No rate limiting on authenticated endpoints (DoS vulnerability)
3. Uses ETS table which is in-memory only - resets on deployment
4. IP-based limiting can be bypassed via proxies/VPNs

**Recommendations:**
- Add rate limiting to all authenticated endpoints (especially PDF generation)
- Use Redis or similar for distributed rate limiting
- Implement user-based rate limiting in addition to IP-based
- Consider progressive backoff for repeated failures

---

### 3. [HIGH] Missing CSRF Token Validation on Critical HTML Endpoints

**Location:** `lib/edoc_api_web/controllers/session_controller.ex:11`

```elixir
def create(conn, %{"email" => email, "password" => password}) do
  case Accounts.authenticate_user(email, password) do
```

**Issue:** The `:browser` pipeline includes `protect_from_forgery`, but there's no visible CSRF token verification being actively used in forms. The session controller accepts POST directly.

**Verification Needed:** Check that CSRF tokens are properly rendered in forms and validated on submit.

---

### 4. [HIGH] Potential Information Disclosure in Error Responses

**Location:** `lib/edoc_api_web/error_mapper.ex:70-79`

```elixir
defp extract_message(details) when is_map(details) do
  {message, details} = Map.pop(details, :message)

  case message do
    nil ->
      {string_message, remaining} = Map.pop(details, "message")
      {string_message, normalize_details(remaining)}
```

**Issue:** Error details may leak internal implementation details. The `inspect/1` function is used in several controllers:

- `lib/edoc_api_web/controllers/auth_controller.ex:28`
- `lib/edoc_api_web/controllers/auth_controller.ex:104`
- `lib/edoc_api_web/controllers/buyers_controller.ex:69`, `:94`, `:114`

```elixir
{:error, reason} ->
  ErrorMapper.unprocessable(conn, "signup_failed", %{reason: inspect(reason)})
```

**Recommendation:** Never return `inspect(reason)` to clients. Log detailed errors server-side but return generic error messages to users.

---

### 5. [MEDIUM] JWT Token Has Long Expiry (7 Days)

**Location:** `lib/edoc_api/auth/token.ex:6`

```elixir
@ttl_seconds 60 * 60 * 24 * 7  # 7 days
```

**Risk:** If a JWT is compromised, attacker has access for a full week. No refresh token mechanism exists.

**Recommendations:**
- Reduce access token TTL to 15-60 minutes
- Implement refresh token rotation
- Add token revocation on logout/security events
- Consider adding device/IP tracking

---

### 6. [MEDIUM] No Account Lockout After Failed Login Attempts

**Location:** `lib/edoc_api/accounts.ex:22-35`

```elixir
def authenticate_user(email, password) do
  case get_user_by_email(email) do
    nil ->
      Argon2.no_user_verify()
      Errors.business_rule(:invalid_credentials, %{email: email})
```

**Issue:** While `Argon2.no_user_verify()` provides timing attack protection, there's no account lockout mechanism. This allows brute force attacks.

**Recommendation:** Implement progressive delays and account lockout after N failed attempts:
- 5 attempts: 5 minute lockout
- 10 attempts: 30 minute lockout
- 15 attempts: 1 hour lockout + email notification

---

### 7. [MEDIUM] Missing Authorization Headers for PDF Downloads

**Location:** `lib/edoc_api_web/controllers/invoice_controller.ex:94-126`

```elixir
def pdf(conn, %{"id" => id}) do
  user = conn.assigns.current_user
  conn = put_layout(conn, false)

  case Invoicing.get_invoice_for_user(user.id, id) do
    nil ->
      ErrorMapper.not_found(conn, "invoice_not_found")
```

**Issue:** PDF endpoints return files that may be cached or shared. No authorization metadata is set on responses.

**Recommendation:**
```elixir
conn
|> put_resp_header("X-Content-Type-Options", "nosniff")
|> put_resp_header("Cache-Control", "private, no-store, max-age=0")
|> put_resp_content_type("application/pdf")
```

---

### 8. [MEDIUM] Email Address Enumeration via Signup/Login

**Locations:**
- `lib/edoc_api_web/controllers/auth_controller.ex:82-91`
- `lib/edoc_api_web/controllers/signup_controller.ex:44-50`

The application reveals whether an email exists:
- `/auth/resend-verification` returns "user_not_found" for non-existent emails
- Signup redirects to login if email already exists

**Recommendation:** Return generic messages for both existing and non-existent emails.

---

### 9. [MEDIUM] Direct Repo.delete Without Authorization Check

**Location:** `lib/edoc_api_web/controllers/companies_controller.ex:189`

```elixir
EdocApi.Repo.delete(EdocApi.Repo.get(EdocApi.Core.CompanyBankAccount, id))
```

**Issue:** While there's a check `accounts = Payments.list_company_bank_accounts_for_user(user.id)`, the final delete uses `Repo.get` + `Repo.delete` directly. If there's a TOCTOU race condition, unauthorized deletion could occur.

**Recommendation:** Always delete by ID with user_id in the WHERE clause:
```elixir
from(a in CompanyBankAccount, where: a.id == ^id and a.company_id == ^company_id)
|> Repo.delete_all()
```

---

### 10. [MEDIUM] Insufficient Input Validation on ID Parameters

**Locations:** Multiple controllers use pattern matching that assumes valid UUID format

```elixir
def show(conn, %{"id" => id}) do
```

**Issue:** No UUID format validation before database query. Invalid UUIDs may cause database errors.

**Recommendation:** Add UUID validation plug:
```elixir
def validate_uuid(conn, _opts) do
  conn.params["id"] |> validate_uuid_format()
end
```

---

### 11. [MEDIUM] Missing Content Security Policy for Inline Scripts

**Location:** `config/runtime.exs:69-70`

```elixir
"content-security-policy" =>
  "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://cdn.tailwindcss.com; ..."
```

**Issue:** `'unsafe-inline'` for scripts significantly reduces CSP protection. Tailwind CDN is loaded from external source.

**Recommendations:**
- Use nonce-based CSP for inline scripts
- Host Tailwind CSS locally or use build process
- Consider `strict-dynamic` for better security

---

### 12. [MEDIUM] No Request Body Size Limits

**Location:** `lib/edoc_api_web/endpoint.ex:48-52`

```elixir
plug(Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library()
)
```

**Issue:** No `length` option set. Large payloads could cause DoS.

**Recommendation:**
```elixir
plug(Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library(),
  length: 10_000_000  # 10MB limit
)
```

---

### 13. [MEDIUM] Sensitive Data in Logs

**Locations:**
- `lib/edoc_api_web/controllers/signup_controller.ex:30`
- `lib/edoc_api/invoicing.ex:895, 901, 907`

```elixir
Logger.info("Verification email sent to #{email}")
```

**Issue:** Email addresses are logged. If logs are leaked, user privacy is compromised.

**Recommendation:** Hash or truncate PII in logs:
```elixir
Logger.info("Verification email sent to #{String.slice(email, 0..3)}...")
```

---

### 14. [LOW] Missing HTTP Security Headers

**Location:** `config/runtime.exs:68-71`

Only CSP is set. Missing recommended headers:
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `Permissions-Policy`
- `Referrer-Policy`

**Recommendation:** Add these headers in production config.

---

### 15. [LOW] Potential Session Fixation on Login

**Location:** `lib/edoc_api_web/controllers/session_controller.ex:26-31`

```elixir
conn
|> put_session(:user_id, user.id)
|> assign(:current_user, user)
```

**Issue:** No explicit session regeneration after login. While Phoenix does this by default, it should be explicit.

**Recommendation:**
```elixir
conn
|> configure_session(renew: true)
|> put_session(:user_id, user.id)
```

---

## API Design Improvements

### 1. Inconsistent Error Response Format

**Issue:** Multiple error response formats exist across the API:
- `auth_controller.ex` returns different structures
- Some endpoints return `{error: "code"}`, others return additional fields

**Recommendation:** Standardize on a single error format:
```json
{
  "error": "error_code",
  "message": "Human-readable message",
  "details": {},
  "request_id": "uuid"
}
```

---

### 2. Missing API Versioning Strategy

**Location:** `lib/edoc_api_web/router.ex:46`

Currently uses `/v1` prefix but no migration/compatibility strategy exists.

**Recommendation:**
- Document API versioning policy
- Implement deprecation warnings
- Consider date-based versioning (`/v2024-02-17`)

---

### 3. No Pagination Metadata for Collections

**Locations:**
- `lib/edoc_api_web/controllers/invoice_controller.ex:37-40`
- `lib/edoc_api_web/controllers/buyers_controller.ex:26-27`

```elixir
json(conn, %{
  invoices: Enum.map(invoices, &InvoiceSerializer.to_map/1),
  meta: %{page: page, page_size: page_size}
})
```

**Issue:** Missing `total_count`, `total_pages`, `has_next`, `has_prev` metadata.

**Recommendation:** Add complete pagination metadata.

---

### 4. Inconsistent ID Parameter Types

Some endpoints accept UUID strings, others accept both UUID and integer-like strings. No consistent validation.

**Recommendation:** Validate all ID parameters as UUID before database query.

---

### 5. Missing Conditional Request Support

**Issue:** No ETag or Last-Modified headers for caching.

**Recommendation:** Implement ETag for invoice/contract PDF endpoints to reduce bandwidth.

---

### 6. No Bulk Operations

**Issue:** Deleting/updating multiple items requires multiple requests.

**Recommendation:** Add bulk delete/update endpoints with proper authorization.

---

### 7. Missing OpenAPI/Swagger Documentation

**Issue:** No machine-readable API documentation.

**Recommendation:** Add `open_api_spex` or similar for API documentation.

---

### 8. Inconsistent HTTP Status Codes

**Examples:**
- `invoice_controller.ex` returns 422 for various business rule violations
- Some validation errors return 400, others 422

**Recommendation:** Document and standardize status code usage:
- 400: Invalid request format
- 401: Not authenticated
- 403: Not authorized
- 404: Resource not found
- 422: Business rule validation failure
- 429: Rate limited
- 500: Internal server error

---

### 9. No Partial Response Support

**Issue:** Clients always get full objects. No field selection.

**Recommendation:** Consider implementing GraphQL or JSON:API sparse fieldsets.

---

### 10. Missing Webhook Support

**Issue:** No real-time notifications for invoice status changes.

**Recommendation:** Add webhook system for events like `invoice.issued`, `invoice.paid`.

---

### 11. Rate Limit Headers Not Standardized

**Location:** `lib/edoc_api_web/plugs/rate_limit.ex:28`

Only `retry-after` is set. Missing standard rate limit headers:
- `RateLimit-Limit`
- `RateLimit-Remaining`
- `RateLimit-Reset`

---

### 12. No Request ID Tracing

**Location:** `lib/edoc_api_web/endpoint.ex:45`

`Plug.RequestId` is added but `request_id` may not be consistently available in error responses.

**Recommendation:** Ensure all error responses include request_id for debugging.

---

## Positive Security Findings

1. **SQL Injection Protection:** Ecto parameterized queries used throughout
2. **Password Storage:** Argon2 with proper salt
3. **Authentication:** JWT with proper claims validation
4. **Email Verification:** Tokens properly hashed using SHA-256
5. **CSRF Protection:** `protect_from_forgery` enabled in browser pipeline
6. **Secure Cookies:** `secure` and `same_site` properly configured
7. **HSTS Enabled:** `force_ssl: [hsts: true]` in production
8. **Tenant Isolation:** User/company scoping on queries

---

## Priority Action Items

### Immediate (This Sprint)
1. Move `signing_salt` to environment variable
2. Remove `inspect(reason)` from all error responses
3. Add request body size limits

### Short Term (Next Sprint)
4. Implement account lockout for failed logins
5. Add rate limiting to authenticated endpoints
6. Standardize error response format

### Medium Term (Next Quarter)
7. Implement refresh token mechanism
8. Add comprehensive API documentation
9. Implement webhook system

---

## Testing Recommendations

1. Add security-focused tests:
   - Authentication bypass attempts
   - Authorization boundary testing
   - Rate limit enforcement
   - Input validation fuzzing

2. Add API contract tests to ensure breaking changes are caught

3. Implement dependency scanning (Mix Audit)

---

## Compliance Notes

- **GDPR:** Consider adding right to data export/deletion
- **Audit Logging:** Consider logging all financial document access
- **Data Retention:** No documented retention policy for deleted invoices

---

*Report generated by Claude Code Security Audit*
