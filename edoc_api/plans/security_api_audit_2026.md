# EdocApi Security & API Audit Report

## February 2026

---

## Executive Summary

This audit reviews the EdocApi codebase for security vulnerabilities and API design improvements. Previous audits (documented in `edoc_audit_report.md` and `audit_from_codex.md`) have addressed many issues. This report focuses on **remaining vulnerabilities** and **new recommendations**.

### Risk Classification

- 🔴 **Critical**: Immediate security risk, exploitable in production
- 🟠 **High**: Significant risk, should be addressed soon
- 🟡 **Medium**: Moderate risk, address in regular development cycle
- 🟢 **Low**: Minor issue or best practice recommendation

---

## 1. Security Findings

### 1.1 PDF Generation External Dependency 🔴 **Critical**

**Location:** [`lib/edoc_api/pdf.ex:16`](lib/edoc_api/pdf.ex:16)

**Issue:** The `html_to_pdf/1` function calls `wkhtmltopdf` without checking if the binary exists. If the binary is missing or fails, the application crashes or returns cryptic errors.

**Current Code:**

```elixir
case System.cmd("wkhtmltopdf", args, stderr_to_stdout: true) do
  {_out, 0} -> ...
  {out, code} -> {:error, {:wkhtmltopdf_failed, code, out}}
end
```

**Problems:**

1. No pre-flight check for binary availability
2. No timeout on external command (can hang indefinitely)
3. Temporary files may remain if process crashes
4. Error messages leak internal details

**Recommendation:**

```elixir
def html_to_pdf(html) when is_binary(html) do
  # Check binary availability at startup, not runtime
  unless binary_available?(), do: {:error, :pdf_generator_not_available}

  # Use Task with timeout
  task = Task.async(fn -> do_generate_pdf(html) end)

  case Task.yield(task, 30_000) || Task.shutdown(task) do
    {:ok, result} -> result
    nil -> {:error, :timeout}
  end
end

defp binary_available? do
  System.find_executable("wkhtmltopdf") != nil
end
```

**Additional Actions:**

- Add application startup check for `wkhtmltopdf`
- Set maximum execution time (30 seconds recommended)
- Use `Temp.Phil` or similar for secure temp file handling

---

### 1.2 Bank Account Default Switching Race Condition 🟠 **High**

**Location:** [`lib/edoc_api/payments.ex:77-105`](lib/edoc_api/payments.ex:77)

**Issue:** The `set_default_bank_account/2` function has a time window where no default exists:

```elixir
# Step 1: Reset ALL defaults
CompanyBankAccount.reset_all_defaults(company.id)

# Step 2: Set new default (gap exists here!)
{:ok, acc} = bank_account |> ... |> Repo.update()
```

**Attack Scenario:**

1. User A starts setting account X as default
2. Reset completes (no defaults exist)
3. User A's request reads company state (no default)
4. User A's update completes
5. System has no default for a brief moment

**Recommendation:**

```elixir
def set_default_bank_account(user_id, bank_account_id) do
  Repo.transaction(fn ->
    # Lock the company row first to prevent concurrent modifications
    company = get_company_or_rollback(user_id)

    # Use single atomic update with CTE or raw SQL
    query = """
    UPDATE company_bank_accounts
    SET is_default = (id = $1)
    WHERE company_id = $2
    """
    Repo.query!(query, [bank_account_id, company.id])

    Repo.get(CompanyBankAccount, bank_account_id)
  end)
end
```

---

### 1.3 BIN/IIN Checksum Validation Disabled 🟠 **High**

**Location:** [`lib/edoc_api/validators/bin_iin.ex:42-48`](lib/edoc_api/validators/bin_iin.ex:42)

**Issue:** The checksum validation function exists but is **not called** in `validate/2`:

```elixir
def validate(changeset, field) do
  changeset
  |> validate_length(field, is: @bin_iin_length)
  |> validate_format(field, @bin_iin_pattern, message: "must contain exactly 12 digits")
  # NOTE: checksum validation is NOT called!
end
```

The comment says "Full checksum validation is currently disabled" but the function `valid_checksum?/1` exists and appears correct.

**Risk:** Invalid BINs like `000000000000` or `111111111111` pass validation.

**Recommendation:** Enable checksum validation:

```elixir
def validate(changeset, field) do
  changeset
  |> validate_length(field, is: @bin_iin_length)
  |> validate_format(field, @bin_iin_pattern, message: "must contain exactly 12 digits")
  |> validate_checksum(field)  # Enable this!
end

defp validate_checksum(changeset, field) do
  case get_change(changeset, field) do
    nil -> changeset
    value ->
      if valid_checksum?(value), do: changeset,
      else: add_error(changeset, field, "invalid checksum")
  end
end
```

---

### 1.4 Session Security Improvements 🟡 **Medium**

**Location:** [`lib/edoc_api_web/endpoint.ex:8-14`](lib/edoc_api_web/endpoint.ex:8)

**Current Configuration:**

```elixir
@session_options [
  store: :cookie,
  key: "_edoc_api_key",
  signing_salt: "SYV+DX7i",
  same_site: if(@session_secure, do: "Strict", else: "Lax"),
  secure: @session_secure
]
```

**Issues:**

1. **Signing salt is hardcoded** in source code (should be in environment)
2. **No session expiration** configured
3. **SameSite: Strict** may break OAuth flows if added later

**Recommendation:**

```elixir
@session_options [
  store: :cookie,
  key: "_edoc_api_key",
  signing_salt: Application.get_env(:edoc_api, :session_signing_salt) ||
    raise("SESSION_SIGNING_SALT not configured"),
  same_site: "Lax",  # More compatible, still prevents CSRF
  secure: @session_secure,
  max_age: 14 * 24 * 60 * 60  # 14 days
]
```

---

### 1.5 Missing Rate Limiting on Additional Endpoints 🟡 **Medium**

**Location:** [`lib/edoc_api_web/router.ex`](lib/edoc_api_web/router.ex)

**Current Rate Limited Endpoints:**

- `/v1/auth/signup` ✅
- `/v1/auth/login` ✅

**Missing Rate Limiting:**

- `/v1/auth/resend-verification` - Can be abused for email spam
- `/v1/auth/verify` - Token enumeration attacks
- PDF generation endpoints - Resource exhaustion

**Recommendation:**

```elixir
scope "/v1", EdocApiWeb do
  pipe_through([:api, :auth_rate_limit])

  post("/auth/resend-verification", AuthController, :resend_verification)
end

# Separate pipeline for PDF rate limiting
pipeline :pdf_rate_limit do
  plug(EdocApiWeb.Plugs.RateLimit, limit: 10, window_seconds: 60)
end
```

---

### 1.6 Error Information Leakage 🟡 **Medium**

**Location:** Multiple controllers

**Issue:** Error responses include internal details:

```elixir
# lib/edoc_api_web/controllers/auth_controller.ex:28
ErrorMapper.unprocessable(conn, "signup_failed", %{reason: inspect(reason)})
```

The `inspect(reason)` can leak:

- Internal module names
- Database structure
- Stack traces in some cases

**Recommendation:**

```elixir
# Log internally, return generic message
Logger.warning("Signup failed: #{inspect(reason)}")
ErrorMapper.unprocessable(conn, "signup_failed", %{
  message: "Unable to create account. Please try again."
})
```

---

### 1.7 Contract Update Partial Data Loss 🟡 **Medium**

**Location:** [`lib/edoc_api/core.ex:111-134`](lib/edoc_api/core.ex:111)

**Issue:** Contract update clears items before creating new ones:

```elixir
contract
|> Ecto.Changeset.change()
|> Ecto.Changeset.put_assoc(:contract_items, [])
|> Repo.update()  # Items deleted here!

with {:ok, updated_contract} <- ...,
     {:ok, _} <- create_contract_items(...) do  # If this fails, items are gone!
```

**Recommendation:** Use `Ecto.Multi` for atomic operations:

```elixir
Ecto.Multi.new()
|> Ecto.Multi.update(:contract, contract_changeset)
|> Ecto.Multi.delete_all(:delete_items, items_query)
|> Ecto.Multi.insert_all(:insert_items, ContractItem, new_items)
|> Repo.transaction()
```

---

### 1.8 Missing CSRF Protection Verification 🟢 **Low**

**Location:** HTML controllers

**Issue:** While `protect_from_forgery` is in the browser pipeline, there's no explicit verification that it's working for HTMX requests.

**Recommendation:** Add CSRF token to HTMX headers:

```elixir
# In layout
<meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()}>

# Configure HTMX
hx-headers='{"x-csrf-token": document.querySelector('meta[name="csrf-token"]').content}'
```

---

## 2. API Design Improvements

### 2.1 Inconsistent Pagination Metadata 🟡 **Medium**

**Location:** [`lib/edoc_api_web/controllers/invoice_controller.ex:28-39`](lib/edoc_api_web/controllers/invoice_controller.ex:28)

**Current Response:**

```json
{
  "invoices": [...],
  "meta": {"page": 1, "page_size": 50}
}
```

**Missing:**

- `total_count` - Total number of records
- `total_pages` - Total number of pages
- `has_next` / `has_prev` - Navigation hints

**Recommendation:**

```json
{
  "invoices": [...],
  "meta": {
    "page": 1,
    "page_size": 50,
    "total_count": 247,
    "total_pages": 5,
    "has_next": true,
    "has_prev": false
  }
}
```

---

### 2.2 Missing API Versioning Header 🟢 **Low**

**Issue:** API responses don't include version information.

**Recommendation:** Add header to all API responses:

```elixir
plug :put_api_version

defp put_api_version(conn, _opts) do
  put_resp_header(conn, "x-api-version", "1.0.0")
end
```

---

### 2.3 Missing Request ID in All Responses 🟢 **Low**

**Location:** [`lib/edoc_api_web/error_mapper.ex:90-92`](lib/edoc_api_web/error_mapper.ex:90)

**Issue:** Request ID is only included in error responses, not success responses.

**Recommendation:** Add to all API responses:

```elixir
# In endpoint or router
plug :assign_request_id

defp assign_request_id(conn, _opts) do
  request_id = Plug.RequestId.get_request_id(conn)
  assign(conn, :request_id, request_id)
end

# In controllers
def json(conn, data) do
  data = Map.put(data, :request_id, conn.assigns.request_id)
  Controller.json(conn, data)
end
```

---

### 2.4 Missing DELETE Endpoint for Contracts API 🟡 **Medium**

**Location:** [`lib/edoc_api_web/router.ex:77-82`](lib/edoc_api_web/router.ex:77)

**Issue:** API has contract creation and update but no DELETE endpoint:

```elixir
get("/contracts", ContractController, :index)
post("/contracts", ContractController, :create)
get("/contracts/:id", ContractController, :show)
# delete "/contracts/:id" is missing!
```

HTML interface has delete functionality but API doesn't.

**Recommendation:**

```elixir
delete("/contracts/:id", ContractController, :delete)
```

---

### 2.5 Missing Invoice Update Endpoint 🟡 **Medium**

**Location:** [`lib/edoc_api_web/router.ex:73-76`](lib/edoc_api_web/router.ex:73)

**Issue:** API has invoice create but no PUT/PATCH for updates:

```elixir
post("/invoices", InvoiceController, :create)
get("/invoices/:id", InvoiceController, :show)
# put "/invoices/:id" is missing!
```

**Recommendation:**

```elixir
put("/invoices/:id", InvoiceController, :update)
```

---

### 2.6 No Bulk Operations Support 🟢 **Low**

**Issue:** No support for bulk operations (create/update/delete multiple records).

**Recommendation for future:**

```elixir
post("/invoices/bulk", InvoiceController, :bulk_create)
post("/invoices/bulk-delete", InvoiceController, :bulk_delete)
```

---

## 3. Code Quality & Maintainability

### 3.1 Invoice Number Generation Complexity 🟡 **Medium**

**Location:** [`lib/edoc_api/invoicing.ex:437-589`](lib/edoc_api/invoicing.ex:437)

**Issue:** The invoice numbering logic spans 150+ lines with multiple branches:

- Recycled number handling
- Counter creation
- Counter increment
- Overflow handling
- Sequence normalization

**Recommendation:** Extract to dedicated module:

```elixir
defmodule EdocApi.InvoiceNumbering do
  def next_number(company_id, opts \\ [])
  def recycle_number(company_id, number)
  def format_number(sequence)
end
```

---

### 3.2 Hardcoded Country-Specific Logic 🟢 **Low**

**Issue:** Kazakhstan-specific validations are scattered:

| Logic               | Location                               |
| ------------------- | -------------------------------------- |
| BIN/IIN (12 digits) | `validators/bin_iin.ex`                |
| VAT rates (0, 16)   | `vat_rates.ex`                         |
| KBE/KNP codes       | `core/kbe_code.ex`, `core/knp_code.ex` |
| Phone format (+7)   | Not validated                          |

**Recommendation:** Create country behavior:

```elixir
defmodule EdocApi.Countries do
  @callback bin_length() :: integer
  @callback vat_rates() :: [integer]
  @callback phone_pattern() :: Regex.t()
end

defmodule EdocApi.Countries.Kazakhstan do
  @behaviour EdocApi.Countries
  def bin_length, do: 12
  def vat_rates, do: [0, 16]
  def phone_pattern, do: ~r/^\+7/
end
```

---

## 4. Summary of Recommendations

### Immediate Action Required (Critical/High)

| Priority    | Issue                       | Location                | Effort |
| ----------- | --------------------------- | ----------------------- | ------ |
| 🔴 Critical | PDF generation fallback     | `pdf.ex`                | Medium |
| 🟠 High     | Bank account race condition | `payments.ex`           | Low    |
| 🟠 High     | Enable BIN/IIN checksum     | `validators/bin_iin.ex` | Low    |

### Short Term (Medium Priority)

| Priority  | Issue                           | Location      | Effort |
| --------- | ------------------------------- | ------------- | ------ |
| 🟡 Medium | Session security config         | `endpoint.ex` | Low    |
| 🟡 Medium | Rate limit additional endpoints | `router.ex`   | Low    |
| 🟡 Medium | Error information leakage       | Multiple      | Low    |
| 🟡 Medium | Contract update atomicity       | `core.ex`     | Medium |
| 🟡 Medium | Pagination metadata             | Controllers   | Low    |
| 🟡 Medium | Missing API endpoints           | `router.ex`   | Low    |

### Long Term (Low Priority)

| Priority | Issue                       | Location       | Effort |
| -------- | --------------------------- | -------------- | ------ |
| 🟢 Low   | CSRF for HTMX               | Templates      | Low    |
| 🟢 Low   | API versioning header       | Endpoint       | Low    |
| 🟢 Low   | Request ID in all responses | Controllers    | Low    |
| 🟢 Low   | Invoice numbering refactor  | `invoicing.ex` | High   |
| 🟢 Low   | Country-specific module     | Multiple       | High   |

---

## 5. Architecture Recommendations

### 5.1 Add Security Headers Middleware

```elixir
defmodule EdocApiWeb.Plugs.SecurityHeaders do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("x-xss-protection", "1; mode=block")
    |> put_resp_header("permissions-policy", "geolocation=(), microphone=(), camera=()")
  end
end
```

### 5.2 Add Audit Logging

```elixir
defmodule EdocApi.AuditLog do
  def log(user_id, action, resource, metadata \\ %{}) do
    %AuditLog{}
    |> changeset(%{
      user_id: user_id,
      action: action,
      resource: resource,
      metadata: metadata,
      ip_address: Process.get(:remote_ip),
      user_agent: Process.get(:user_agent)
    })
    |> Repo.insert()
  end
end
```

Log important actions:

- User authentication (success/failure)
- Invoice issuance
- Contract signing
- Bank account changes
- Company data modifications

---

## 6. Testing Recommendations

### 6.1 Security Tests to Add

```elixir
# Test rate limiting
describe "rate limiting" do
  test "blocks after 5 failed login attempts"
  test "includes retry-after header"
end

# Test authorization
describe "authorization" do
  test "user cannot access other user's invoices"
  test "user cannot modify issued invoices"
  test "session user cannot access API endpoints"
end

# Test input validation
describe "input validation" do
  test "rejects invalid BIN/IIN checksums"
  test "rejects future issue dates"
  test "rejects negative amounts"
end
```

---

## 7. Monitoring Recommendations

### 7.1 Metrics to Track

- Failed authentication attempts (per IP, per email)
- PDF generation failures and latency
- Invoice/contract creation rate
- API response times by endpoint
- Database query performance

### 7.2 Alerts to Configure

- Multiple failed logins from same IP
- PDF generation failures
- High error rate on any endpoint
- Database connection pool exhaustion

---

## Appendix A: Files Reviewed

- `lib/edoc_api_web/router.ex`
- `lib/edoc_api_web/endpoint.ex`
- `lib/edoc_api_web/plugs/authenticate.ex`
- `lib/edoc_api_web/plugs/authenticate_session.ex`
- `lib/edoc_api_web/plugs/rate_limit.ex`
- `lib/edoc_api_web/controllers/auth_controller.ex`
- `lib/edoc_api_web/controllers/invoice_controller.ex`
- `lib/edoc_api_web/controllers/invoices_controller.ex`
- `lib/edoc_api_web/controllers/session_controller.ex`
- `lib/edoc_api_web/error_mapper.ex`
- `lib/edoc_api_web/controller_helpers.ex`
- `lib/edoc_api/auth/token.ex`
- `lib/edoc_api/accounts.ex`
- `lib/edoc_api/accounts/user.ex`
- `lib/edoc_api/invoicing.ex`
- `lib/edoc_api/payments.ex`
- `lib/edoc_api/core.ex`
- `lib/edoc_api/pdf.ex`
- `lib/edoc_api/errors.ex`
- `lib/edoc_api/validators/bin_iin.ex`
- `lib/edoc_api/core/invoice.ex`
- `config/runtime.exs`
- `config/prod.exs`

---

## Appendix B: References

- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [Phoenix Security Guide](https://hexdocs.pm/phoenix/security.html)
- [Elixir Security Checklist](https://github.com/devon_estate/elixir_security_checklist)
