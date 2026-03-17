# Project Health Audit: Edoc API

**Generated**: 2026-02-19
**Mode**: full
**Project**: Electronic Document Invoicing API (Elixir/Phoenix)

---

## Executive Summary

### Health Score: C+ (70/100)

| Category | Score | Status |
|----------|-------|--------|
| Architecture | 75/100 | Moderate |
| Performance | 60/100 | Needs Attention |
| Security | 72/100 | Moderate |
| Test Quality | 55/100 | Needs Work |
| Dependencies | 90/100 | Good |

### Overall Grade: C+

The EdocAPI project has a solid foundation with good patterns for authentication, input validation, and database design. However, there are critical gaps in test coverage (especially for authentication/authorization), performance concerns (missing indexes, no caching), and security issues (hardcoded secrets).

---

## Critical Issues (Must Address)

### Security (Critical)
1. **Hardcoded secrets in configuration files** - JWT secret and secret_key_base are hardcoded in `config/config.exs`, `config/dev.exs`, and `config/test.exs`
2. **Missing log parameter filtering** - Sensitive data may be logged in plain text
3. **Information disclosure** - Using `inspect(reason)` in error responses may leak internal details

### Testing (Critical)
4. **Zero test coverage for authentication** - No tests for signup, login, email verification flows
5. **Zero test coverage for authorization** - No tests verifying user isolation or company ownership
6. **No tests for payments module** - Financial transactions unvalidated
7. **New Acts feature has zero test coverage**

### Performance (High)
8. **Missing database indexes** on `invoices.status` and `contracts.status`
9. **Unpaginated HTML list views** - Will cause memory issues as data grows
10. **No caching layer** - Reference data (KBE/KNP codes, banks) fetched on every request

### Architecture (Moderate)
11. **EdocApi.Core is an anti-pattern** - Not a proper context, just a delegation facade
12. **29 circular dependencies** - Should be reduced where possible

---

## Top Recommendations (Priority Order)

### Immediate (This Sprint)
1. **Remove hardcoded secrets** from config files
   ```elixir
   config :edoc_api, EdocApi.Auth, jwt_secret:
     System.get_env("JWT_SECRET") || raise "JWT_SECRET not set"
   config :phoenix, :filter_parameters, ["password", "token", "secret", "csrf"]
   ```

2. **Add authentication tests** - Create `test/edoc_api_web/controllers/auth_controller_test.exs`
   - Test signup, login, verification flows
   - Test JWT token generation and validation

3. **Add database indexes** for performance
   ```elixir
   create(index(:invoices, [:status]))
   create(index(:contracts, [:status]))
   create(index(:contracts, [:company_id, :status]))
   ```

4. **Add pagination to HTML list views** - Prevent memory exhaustion

### Short-term (Next 2 Sprints)
5. **Add authorization tests** - Verify user isolation and company ownership enforcement
6. **Implement reference data caching** - Cache KBE/KNP codes and banks
7. **Enable async: true on all controller tests** - 30-40% test speedup
8. **Add Acts feature tests** - New feature is completely untested

### Long-term (Backlog)
9. **Extract Contracts context** from EdocApi.Core
10. **Install Oban for background jobs** - Move PDF generation to background
11. **Add property-based tests** for VAT calculations
12. **Consider Phoenix 1.8 upgrade** - Requires testing

---

## Detailed Findings by Category

## Architecture (75/100) - Moderate

### Strengths
- ✅ Clear separation between API and HTML controllers
- ✅ Context pattern used consistently
- ✅ Good schema organization in `core/` directory
- ✅ Validator modules properly extracted

### Weaknesses
- ❌ `EdocApi.Core` is not a proper context - just a delegation facade
- ❌ `Invoicing` context is bloated (991 lines)
- ❌ Inconsistent schema location (User in `accounts/`, others in `core/`)
- ❌ 29 circular dependencies
- ❌ No explicit behaviours or protocols

### Key Recommendations
1. Extract `EdocApi.Contracts` from `EdocApi.Core`
2. Split invoice number generation into separate context
3. Introduce behaviours for external service boundaries

---

## Performance (60/100) - Needs Attention

### Strengths
- ✅ Most foreign keys have indexes
- ✅ Pagination implemented for API endpoints
- ✅ Efficient use of Ecto

### Weaknesses
- ❌ Missing indexes on `invoices.status` and `contracts.status`
- ❌ HTML list views unpaginated
- ❌ No caching layer
- ❌ Leading wildcard searches prevent index usage
- ❌ Bulk operations done in loops
- ❌ No background job processor

### Key Recommendations
1. Add status indexes for invoices and contracts
2. Add pagination to all list views
3. Implement caching for reference data
4. Consider Oban for background PDF generation

---

## Security (72/100) - Moderate

### Strengths
- ✅ Argon2 for password hashing (industry best practice)
- ✅ Timing-safe authentication prevents user enumeration
- ✅ Proper JWT implementation with Joken
- ✅ All data access scoped by user/company
- ✅ No SQL injection vulnerabilities
- ✅ HEEX auto-escapes by default
- ✅ CSRF protection enabled

### Weaknesses
- ❌ **Hardcoded secrets** in config files (Critical)
- ❌ Missing log parameter filtering
- ❌ Information disclosure through `inspect(reason)`
- ❌ Rate limiting only on auth endpoints
- ❌ Weak CSP policy with `unsafe-inline`
- ❌ Missing security headers
- ❌ No token revocation on logout

### Key Recommendations
1. Remove all hardcoded secrets from config files
2. Add `filter_parameters` configuration
3. Sanitize error messages
4. Expand rate limiting to all endpoints
5. Tighten CSP policy

---

## Test Quality (55/100) - Needs Work

### Strengths
- ✅ 17 test files covering core business logic
- ✅ Good setup patterns with fixtures
- ✅ Sandbox isolation configured
- ✅ Strong assertion patterns
- ✅ No sleep-based timing issues

### Weaknesses
- ❌ **Zero coverage** for authentication/authorization (Critical)
- ❌ **Zero coverage** for payments module (Critical)
- ❌ **Zero coverage** for Acts feature (Critical)
- ❌ **Zero coverage** for companies module
- ❌ Controller tests missing `async: true` (slows CI)
- ❌ No integration test suite
- ❌ No mock framework (Mox) for external services

### Key Recommendations
1. Add authentication test suite (highest priority)
2. Add authorization tests for user isolation
3. Enable `async: true` on controller tests
4. Add Acts feature tests
5. Install ExMachina for better factory patterns

---

## Dependencies (90/100) - Good

### Strengths
- ✅ No known vulnerabilities detected
- ✅ All dependencies are in use
- ✅ Permissive licenses (MIT/Apache-2.0)
- ✅ Up-to-date versions

### Weaknesses
- ❌ Phoenix 1.7 → 1.8 available (major version)
- ❌ Elixir 1.14 → 1.17+ available
- ❌ Several minor updates available

### Key Recommendations
1. Apply patch updates (ecto_sql, tidewave)
2. Plan Phoenix 1.8 upgrade carefully
3. Consider Elixir version upgrade

---

## Cross-Category Correlations

### Test Coverage ↔ Security
The lack of authentication and authorization tests represents the highest risk. Security primitives (Argon2, scoping) appear sound, but without tests, security guarantees cannot be verified.

### Performance ↔ Architecture
The bloated `Invoicing` context contributes to performance issues. Splitting it would enable better caching and optimization strategies.

### Dependencies ↔ Architecture
The use of newer Phoenix 1.8 features (which this project doesn't have yet) could help address some architectural concerns like better LiveView patterns.

---

## Action Plan

### Sprint 1 (Immediate)
- [ ] Remove hardcoded secrets from config files
- [ ] Add `filter_parameters` to config
- [ ] Add status indexes to invoices and contracts tables
- [ ] Create authentication test suite
- [ ] Add pagination to HTML list views

### Sprint 2 (Short-term)
- [ ] Add authorization tests for user isolation
- [ ] Implement reference data caching
- [ ] Enable async: true on controller tests
- [ ] Add Acts feature tests
- [ ] Sanitize error messages (remove inspect())

### Sprint 3+ (Long-term)
- [ ] Extract Contracts context from Core
- [ ] Install Oban for background jobs
- [ ] Add property-based tests
- [ ] Plan Phoenix 1.8 upgrade
- [ ] Add structured security logging

---

## Metrics Summary

| Metric | Value | Target |
|--------|-------|--------|
| Test Files | 17 | 30+ |
| Test Coverage | ~40% | 80% |
| Circular Dependencies | 29 | <15 |
| Hardcoded Secrets | 3 | 0 |
| Missing Indexes | 4 | 0 |
| Critical Vulnerabilities | 1 (secrets) | 0 |

---

## Conclusion

The EdocAPI project demonstrates solid engineering fundamentals with proper use of Elixir/Phoenix patterns. The codebase is clean and follows many best practices. However, the lack of test coverage for security-critical paths (authentication, authorization) and the presence of hardcoded secrets represent significant risks that should be addressed immediately.

With focused effort on the critical items identified above, this project can quickly move from a "C+" to a "B+" rating. The foundation is strong—what's needed is systematic attention to the identified gaps.

---

## Reports Generated

- `.claude/audit/reports/arch-review.md` - Architecture analysis
- `.claude/audit/reports/perf-audit.md` - Performance analysis
- `.claude/audit/reports/security-audit.md` - Security analysis
- `.claude/audit/reports/test-audit.md` - Test coverage analysis
- `.claude/audit/reports/deps-audit.md` - Dependency analysis
