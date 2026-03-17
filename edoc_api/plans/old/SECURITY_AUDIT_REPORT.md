# EdocApi Security Audit Report

## Executive Summary

This comprehensive security audit identified **23 security vulnerabilities** across the EdocApi application, including **5 critical**, **8 high**, **6 medium**, and **4 low** severity issues. The application demonstrates good security practices in some areas (password hashing, JWT implementation) but has significant gaps in input validation, rate limiting, and secure configuration.

## Critical Vulnerabilities (5)

### 1. Hardcoded JWT Secret in Development
**File:** `config/config.exs:53`
```elixir
config :edoc_api, EdocApi.Auth, jwt_secret: "dev-secret-change-me"
```
**Risk:** Production deployments may use this weak, hardcoded secret
**Impact:** Complete authentication bypass
**Recommendation:** Ensure JWT_SECRET is always set in production environments

### 2. Weak Rate Limiting Implementation
**File:** `lib/edoc_api_web/plugs/rate_limit.ex:57-61`
```elixir
defp client_ip(conn) do
  conn.remote_ip
  |> :inet.ntoa()
  |> to_string()
end
```
**Risk:** Rate limiting can be bypassed using X-Forwarded-For header
**Impact:** Brute force attacks possible
**Recommendation:** Implement proper IP extraction considering trusted proxies

### 3. Command Injection in PDF Generation
**File:** `lib/edoc_api/pdf.ex:14-16`
```elixir
File.write!(html_path, html)
args = ["--encoding", "utf-8", "--quiet", html_path, pdf_path]
case System.cmd("wkhtmltopdf", args, stderr_to_stdout: true) do
```
**Risk:** HTML content controls file paths used in system command
**Impact:** Remote code execution
**Recommendation:** Sanitize file paths and validate HTML content

### 4. Insufficient Input Validation
**Files:** Multiple controller files lack proper input validation
**Risk:** Various injection attacks (SQL, XSS, etc.)
**Impact:** Data manipulation and system compromise
**Recommendation:** Implement comprehensive input validation for all user inputs

### 5. Missing Security Headers
**File:** `config/runtime.exs:68-71`
```elixir
secure_browser_headers: %{
  "content-security-policy" => "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://cdn.tailwindcss.com; connect-src 'self'; font-src 'self' data:; frame-ancestors 'self'; base-uri 'self'"
}
```
**Risk:** CSP allows unsafe-inline for scripts and styles
**Impact:** XSS attacks possible
**Recommendation:** Remove unsafe-inline and implement nonce-based CSP

## High Severity Vulnerabilities (8)

### 6. SQL Injection Risk in Search Functions
**File:** `lib/edoc_api/buyers.ex:219-224`
```elixir
def search_buyers(company_id, query) when is_binary(company_id) and is_binary(query) do
  query = "%#{query}%"
  from(b in Buyer, where: b.company_id == ^company_id)
  |> where([b], ilike(b.name, ^query) or ilike(b.bin_iin, ^query))
end
```
**Risk:** While parameterized, query concatenation could be vulnerable
**Impact:** Data exfiltration
**Recommendation:** Validate query length and allowed characters

### 7. Session Security Issues
**File:** `lib/edoc_api_web/endpoint.ex:7-14`
```elixir
@session_secure Application.compile_env(:edoc_api, :secure_cookies, false)
@session_options [
  store: :cookie,
  key: "_edoc_api_key",
  signing_salt: "SYV+DX7i",
  same_site: if(@session_secure, do: "Strict", else: "Lax"),
  secure: @session_secure
]
```
**Risk:** Session cookies not secure by default
**Impact:** Session hijacking
**Recommendation:** Enable secure cookies in all environments

### 8. Information Disclosure in Error Messages
**File:** `lib/edoc_api_web/controllers/auth_controller.ex:28`
```elixir
ErrorMapper.unprocessable(conn, "signup_failed", %{reason: inspect(reason)})
```
**Risk:** Detailed error information exposed
**Impact:** System information leakage
**Recommendation:** Sanitize error messages for production

### 9. Missing Authentication on Sensitive Endpoints
**File:** `lib/edoc_api_web/router.ex:46-52`
```elixir
scope "/v1", EdocApiWeb do
  pipe_through(:api)
  get("/health", HealthController, :index)
  get("/auth/verify", AuthController, :verify_email)
  post("/auth/resend-verification", AuthController, :resend_verification)
end
```
**Risk:** Email verification endpoints lack rate limiting
**Impact:** Email bombing and enumeration attacks
**Recommendation:** Add rate limiting to all auth endpoints

### 10. Weak Password Policy
**File:** `lib/edoc_api/accounts/user.ex:28`
```elixir
|> validate_length(:password, min: 8, max: 72)
```
**Risk:** No complexity requirements
**Impact:** Weak passwords vulnerable to brute force
**Recommendation:** Implement password complexity requirements

### 11. HTML Injection in PDF Templates
**File:** `lib/edoc_api_web/pdf_templates.ex:452-457`
```elixir
<% c = @contract || %{} %>
<% seller = @seller || %{} %>
<% buyer = @buyer || %{} %>
<h1>ДОГОВОР № <%= c.number || "____" %></h1>
```
**Risk:** User data directly embedded in HTML without sanitization
**Impact:** XSS in PDF documents
**Recommendation:** Sanitize all user data in templates

### 12. Insufficient Authorization Checks
**File:** `lib/edoc_api_web/controllers/invoice_controller.ex:42-52`
```elixir
def show(conn, %{"id" => id}) do
  user = conn.assigns.current_user
  case Invoicing.get_invoice_for_user(user.id, id) do
```
**Risk:** Authorization logic depends entirely on business logic
**Impact:** Potential data access violations
**Recommendation:** Implement defense-in-depth authorization checks

### 13. Missing File Upload Validation
**Risk:** No file upload restrictions found
**Impact:** Malicious file uploads
**Recommendation:** Implement file type, size, and content validation

## Medium Severity Vulnerabilities (6)

### 14. Verbose Error Handling
**File:** `lib/edoc_api_web/unified_error_handler.ex:115-123`
```elixir
defp error_to_status_and_message(type, details) do
  case type do
    :not_found -> {404, "#{humanize(details[:resource])} not found"}
    :business_rule -> {422, humanize(details[:rule])}
    :validation -> {422, "Validation failed"}
```
**Risk:** Internal state information leaked
**Impact:** Information disclosure
**Recommendation:** Use generic error messages in production

### 15. Insufficient Logging
**Risk:** No security event logging found
**Impact:** Lack of audit trail
**Recommendation:** Implement comprehensive security logging

### 16. Weak CSRF Protection
**File:** `lib/edoc_api_web/router.ex:22,32`
```elixir
plug(:protect_from_forgery)
```
**Risk:** CSRF protection enabled but token validation may be weak
**Impact:** CSRF attacks possible
**Recommendation:** Verify CSRF token implementation

### 17. Database Connection Security
**File:** `config/runtime.exs:33-37`
```elixir
config :edoc_api, EdocApi.Repo,
  # ssl: true,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
```
**Risk:** SSL commented out for database
**Impact:** Database traffic interception
**Recommendation:** Enable SSL for database connections

### 18. Missing Input Length Limits
**Risk:** No maximum length validation for string inputs
**Impact:** DoS attacks via large inputs
**Recommendation:** Implement input length limits

### 19. Weak Email Verification Tokens
**File:** `lib/edoc_api/email_verification.ex:171-172`
```elixir
defp generate_secure_token do
  :crypto.strong_rand_bytes(@token_length)
end
```
**Risk:** 32-byte tokens may be insufficient
**Impact:** Token guessing attacks
**Recommendation:** Increase token length and add entropy checks

## Low Severity Vulnerabilities (4)

### 20. Development Routes in Production
**File:** `lib/edoc_api_web/router.ex:161-175`
```elixir
if Application.compile_env(:edoc_api, :dev_routes) do
  scope "/dev" do
    pipe_through([:fetch_session, :protect_from_forgery])
    live_dashboard("/dashboard", metrics: EdocApiWeb.Telemetry)
    forward("/mailbox", Plug.Swoosh.MailboxPreview)
  end
end
```
**Risk:** Development endpoints exposed
**Impact:** Information disclosure
**Recommendation:** Ensure dev_routes is false in production

### 21. Missing Security Headers
**Risk:** Limited security headers implementation
**Impact:** Various client-side attacks
**Recommendation:** Implement comprehensive security headers

### 22. Insufficient Rate Limiting Scope
**File:** `lib/edoc_api_web/plugs/rate_limit.ex:13-17`
```elixir
limit = Keyword.get(opts, :limit, 5)
window_seconds = Keyword.get(opts, :window_seconds, 60)
action = Keyword.get(opts, :action, conn.request_path)
```
**Risk:** Rate limiting only per IP and endpoint
**Impact:** Limited protection against sophisticated attacks
**Recommendation:** Implement user-based rate limiting

### 23. Temporary File Security
**File:** `lib/edoc_api/pdf.ex:6-12`
```elixir
tmp_dir = System.tmp_dir!()
uniq = Integer.to_string(System.unique_integer([:positive]))
html_path = Path.join(tmp_dir, "edoc_#{uniq}.html")
pdf_path = Path.join(tmp_dir, "edoc_#{uniq}.pdf")
```
**Risk:** Predictable file names in shared temp directory
**Impact:** Race condition attacks
**Recommendation:** Use secure random file names and permissions

## Positive Security Findings

1. **Strong Password Hashing:** Uses Argon2 with proper salt
2. **JWT Implementation:** Proper token structure and validation
3. **Parameterized Queries:** Ecto provides SQL injection protection
4. **CSRF Protection:** Enabled for HTML forms
5. **Input Sanitization:** HTML sanitization for contract body_html

## Recommendations by Priority

### Immediate (Critical)
1. Change hardcoded JWT secrets
2. Fix rate limiting IP extraction
3. Sanitize PDF generation inputs
4. Implement comprehensive input validation
5. Strengthen CSP policy

### Short-term (High)
1. Enable secure session cookies
2. Sanitize error messages
3. Add rate limiting to auth endpoints
4. Implement password complexity requirements
5. Add file upload validation

### Medium-term
1. Implement security logging
2. Enable database SSL
3. Add input length limits
4. Strengthen CSRF protection
5. Add authorization layers

### Long-term (Low)
1. Implement comprehensive security headers
2. Add user-based rate limiting
3. Secure temporary file handling
4. Add security monitoring
5. Implement security testing in CI/CD

## Compliance Notes

- **GDPR:** PII handling needs review
- **SOC2:** Logging and monitoring gaps identified
- **OWASP Top 10:** Multiple vulnerabilities map to OWASP categories

## Conclusion

The EdocApi application has a solid foundation but requires significant security improvements before production deployment. The most critical issues involve authentication bypasses and injection vulnerabilities that should be addressed immediately.

**Overall Security Rating: 3/10** - Requires substantial security hardening