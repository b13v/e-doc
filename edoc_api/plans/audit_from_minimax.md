# Security & API Audit Report - Minimax Analysis

**Date:** 2026-02-13  
**Project:** edoc_api (Elixir/Phoenix)  
**Analyzer:** Minimax

---

## 1. Project Overview

- **Framework:** Elixir with Phoenix 1.7.10
- **Database:** PostgreSQL with Ecto ORM
- **Authentication:** JWT (joken) + Argon2 password hashing
- **API Style:** REST JSON API with rate limiting

---

## 2. Critical Security Issues

### 2.1 Hardcoded Secrets

| Location | Issue |
|----------|-------|
| `config/config.exs:53` | Hardcoded JWT secret: `"dev-secret-change-me"` |
| `config/dev.exs` | Hardcoded DB password `"postgres"`, secret_key_base |
| `config/test.exs` | Hardcoded DB password, secret_key_base |

**Recommendation:** Use environment variables in all configs. The `runtime.exs` already does this correctly - apply the same pattern to dev/test configs.

### 2.2 Weak Email Verification Token Hashing

**Location:** `lib/edoc_api/email_verification.ex:176-179`

```elixir
defp hash_token(token) do
  :sha256
  |> :crypto.hash(token)
  |> Base.encode16()
end
```

**Issue:** Using SHA256 for token hashing is weak. Tokens should use constant-time comparison and stronger algorithms.

**Recommendation:** Use a dedicated library like `Plug.Crypto.secure_compare` for timing-safe comparison.

### 2.3 Authorization Bypass Risk in Buyer Deletion

**Location:** `lib/edoc_api_web/controllers/buyers_controller.ex:107`

```elixir
case Buyers.can_delete?(id) do
```

**Issue:** The check doesn't verify company ownership before checking if buyer can be deleted. Could allow enumeration attacks.

**Recommendation:** Verify company ownership first, then check deletion constraints.

---

## 3. Medium Security Issues

### 3.1 Rate Limiter Implementation

**Location:** `lib/edoc_api_web/plugs/rate_limit.ex`

- ETS table is `:public` - should be `:protected`
- In-memory storage resets on restart
- No distributed rate limiting for multi-node deployments

**Recommendation:** Consider Redis-based rate limiting for production. Change ETS table to `:protected`.

### 3.2 Debug Mode in Production

**Location:** `config/runtime.exs:67`

```elixir
debug_errors: true
```

**Recommendation:** Set to `false` in production.

---

## 4. API Improvements

### 4.1 Missing Input Validation

- **IBAN validation:** Currently uses regex, should validate checksum
- **BIN/IIN validation:** Should verify checksum (12-digit Kazakhstan-specific)
- **Email:** Good validation exists, but consider adding disposable email detection

### 4.2 Response Consistency

- Some endpoints return different structures for similar operations
- Consider standardizing error responses with consistent format

### 4.3 Missing Endpoints

| Endpoint | Purpose |
|----------|---------|
| `PATCH /v1/buyers/:id` | Partial update for buyers |
| `POST /v1/invoices/bulk` | Bulk invoice creation |
| `GET /v1/invoices/export` | Export invoices (CSV/Excel) |

### 4.4 Pagination

- No pagination on list endpoints (buyers, invoices, contracts)
- Could cause performance issues with large datasets

**Recommendation:** Implement cursor-based pagination.

---

## 5. Positive Security Practices Found

1. Password hashing with Argon2 (strong)
2. JWT claims validation (issuer, audience, expiration)
3. Resource-based authorization (company ownership checks)
4. Email verification with expiration
5. HTTPS enforced in production (`force_ssl: true`)
6. Content Security Policy headers configured
7. Production config uses environment variables for secrets

---

## 6. Priority Recommendations

### High Priority

1. **Remove hardcoded JWT secret** - Change to environment variable
2. **Fix buyer deletion authorization** - Verify company ownership first
3. **Disable debug_errors in production** - Set to `false`

### Medium Priority

4. **Improve rate limiter** - Use `:protected` ETS table, consider Redis
5. **Add pagination** - Implement cursor-based pagination for list endpoints
6. **Add IBAN checksum validation** - Enhance IBAN validator

### Low Priority

7. **Add bulk operations** - Support bulk invoice creation
8. **Add export endpoint** - CSV/Excel export for invoices
9. **Add PATCH endpoints** - Partial updates for resources

---

## 7. Database Security Notes

- Ecto prevents SQL injection by default (good)
- Consider adding row-level security for multi-tenant isolation
- Add database connection pooling limits to prevent exhaustion

---

## Conclusion

The codebase has a solid security foundation with JWT authentication, Argon2 password hashing, and proper authorization checks. Main concerns are hardcoded secrets in non-production configs and some authorization edge cases. The API design is clean but would benefit from pagination and additional bulk operations.
