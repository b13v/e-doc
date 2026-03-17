# Implementing and Hardening Progress

Last updated: 2026-02-25

## Completed

### Phase 1 - Critical Security Hardening (P0)
- [x] Removed hardcoded auth/session secrets from tracked config and switched to env-driven values.
  - `config/config.exs`
  - `config/dev.exs`
  - `config/test.exs`
  - `config/prod.exs`
  - `config/runtime.exs`
  - `lib/edoc_api_web/endpoint.ex`
- [x] Added sensitive parameter filtering in Phoenix logs.
  - `config/config.exs`
- [x] Removed user-facing `inspect(reason)` leakage and mapped to sanitized error responses.
  - `lib/edoc_api_web/controllers/auth_controller.ex`
  - `lib/edoc_api_web/controllers/buyers_controller.ex`
  - `lib/edoc_api_web/error_mapper.ex`
- [x] Hardened production security headers and CSP.
  - `config/runtime.exs`
- [x] Added request body size cap to parser pipeline.
  - `lib/edoc_api_web/endpoint.ex`

### Phase 2 - Authentication / Session / Abuse Controls (P0-P1)
- [x] Session renewal enabled on login.
  - `lib/edoc_api_web/controllers/session_controller.ex`
- [x] Session and JWT flows aligned to require verified users.
  - `lib/edoc_api_web/plugs/authenticate.ex`
  - `lib/edoc_api_web/plugs/authenticate_session.ex`
- [x] Email enumeration reduced for signup/resend by using generic user-facing responses.
  - `lib/edoc_api_web/controllers/auth_controller.ex`
  - `lib/edoc_api_web/controllers/signup_controller.ex`
- [x] Reduced JWT access token TTL (configurable) and introduced refresh token rotation/revocation.
  - `lib/edoc_api/auth/token.ex`
  - `lib/edoc_api/auth/refresh_token.ex`
  - `lib/edoc_api/accounts.ex`
  - `lib/edoc_api_web/controllers/auth_controller.ex`
  - `lib/edoc_api_web/router.ex`
  - `priv/repo/migrations/20260225120000_add_auth_hardening_fields.exs`
  - `config/config.exs`
  - `config/runtime.exs`
- [x] Added account lockout + progressive delay on failed auth attempts.
  - `lib/edoc_api/accounts.ex`
  - `priv/repo/migrations/20260225120000_add_auth_hardening_fields.exs`

### Phase 3 - Rate Limiting + Request Security (P0-P1)
- [x] Expanded API rate-limiting coverage beyond signup/login.
  - auth verify/resend
  - expensive PDF endpoints
  - protected mutating endpoints
  - `lib/edoc_api_web/router.ex`
- [x] Upgraded ETS limiter to stronger OTP-only behavior (no Redis).
  - user-or-ip subject support
  - proxy-safe forwarded IP parsing
  - periodic ETS cleanup
  - `lib/edoc_api_web/plugs/rate_limit.ex`
- [x] Added standard rate-limit headers.
  - `RateLimit-Limit`
  - `RateLimit-Remaining`
  - `RateLimit-Reset`
  - `Retry-After`
  - `lib/edoc_api_web/plugs/rate_limit.ex`
- [x] Added dedicated rate-limit/auth regression tests.
  - `test/edoc_api_web/plugs/rate_limit_test.exs`
  - `test/edoc_api_web/controllers/auth_controller_test.exs`

### Phase 4 - Data Validation + Transaction Safety (P1) (partial)
- [x] Enabled BIN/IIN checksum validation.
  - `lib/edoc_api/validators/bin_iin.ex`
- [x] Added IBAN checksum validation (mod-97).
  - `lib/edoc_api/validators/iban.ex`
- [x] Updated fixture/test BIN/IIN + IBAN values to checksum-valid data.
  - `test/support/fixtures.ex`
  - `test/edoc_api/buyers_test.exs`
  - `test/edoc_api/legal_forms_test.exs`
  - `test/edoc_api/core/company_bank_account_changeset_test.exs`
  - `test/edoc_api_web/controllers/buyers_controller_test.exs`
  - `test/edoc_api_web/controllers/company_bank_account_controller_test.exs`
- [x] Hardened PDF generation path.
  - executable check
  - command timeout + kill-after
  - sanitized failure mapping
  - safe cleanup
  - `lib/edoc_api/pdf.ex`
- [x] Added PDF response security headers.
  - `cache-control: private, no-store, max-age=0`
  - `pragma: no-cache`
  - `x-content-type-options: nosniff`
  - `lib/edoc_api_web/controllers/invoice_controller.ex`
  - `lib/edoc_api_web/controllers/contract_controller.ex`
- [x] Replaced unsafe direct bank-account delete with scoped delete by company.
  - `lib/edoc_api_web/controllers/companies_controller.ex`
- [x] Added UUID/id validation plug to protected API routes.
  - `lib/edoc_api_web/plugs/validate_uuid.ex`
  - `lib/edoc_api_web/router.ex`
- [ ] Atomic contract item update via `Ecto.Multi` (pending)

### Phase 6 - Performance + Data Access Optimization (P1) (partial)
- [x] Added key missing performance indexes.
  - `invoices.status`
  - `contracts.status`
  - `contracts(company_id, status)`
  - `invoices(user_id, inserted_at)`
  - `priv/repo/migrations/20260225121000_add_performance_indexes.exs`

## Newly Added Tests
- `test/edoc_api/validators/bin_iin_test.exs`
- `test/edoc_api/validators/iban_test.exs`
- `test/edoc_api/accounts_test.exs`
- `test/edoc_api_web/plugs/rate_limit_test.exs`
- `test/edoc_api_web/plugs/validate_uuid_test.exs`
- `test/edoc_api_web/controllers/auth_controller_test.exs`
- Updated PDF assertions:
  - `test/edoc_api_web/controllers/invoice_controller_test.exs`
  - `test/edoc_api_web/controllers/contract_controller_test.exs`

## Pending Next Steps (short horizon)
1. Implement atomic contract item update via `Ecto.Multi`.
2. Continue coverage expansion for `Accounts`, `Payments`, `Companies`, and `Acts`.
3. Normalize collection pagination metadata (`total_count`, `total_pages`, `has_next`, `has_prev`).
4. Add OpenAPI generation + API version/deprecation policy.
