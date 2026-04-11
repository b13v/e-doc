# Password Reset Flow Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a secure RU/KK-localized password reset flow reachable from `/login`, with neutral responses, 24h tokens, one-time use, and request throttling.

**Architecture:** Add a focused `EdocApi.PasswordReset` domain module with DB-backed hashed tokens and explicit contracts, then expose it through a dedicated browser controller and pages. Reuse existing auth/email patterns (`EmailSender`, router pipelines, gettext, flash behavior), and enforce single-winner token consumption in a transaction.

**Tech Stack:** Elixir, Phoenix 1.7, Ecto/Postgres, Swoosh, Gettext, ExUnit.

---

## File Structure

- Create: `lib/edoc_api/password_reset.ex` — token issuance/verification/reset domain logic + throttling rules.
- Create: `lib/edoc_api/password_reset_token.ex` — Ecto schema + changeset for reset tokens.
- Create: `priv/repo/migrations/20260411120000_create_password_reset_tokens.exs` — persistence layer.
- Modify: `lib/edoc_api/accounts.ex` — add `revoke_all_refresh_tokens/1`.
- Modify: `lib/edoc_api/email_sender.ex` — localized password-reset email templates.
- Modify: `lib/edoc_api_web/router.ex` — routes + browser rate-limit pipeline for forgot-password POST.
- Create: `lib/edoc_api_web/controllers/password_reset_controller.ex` — web endpoints.
- Create: `lib/edoc_api_web/controllers/password_reset_html.ex` — embed templates.
- Create: `lib/edoc_api_web/controllers/password_reset_html/new.html.heex` — forgot-password UI.
- Create: `lib/edoc_api_web/controllers/password_reset_html/edit.html.heex` — set-new-password UI.
- Modify: `lib/edoc_api_web/controllers/session_html/new.html.heex` — always-visible “Forgot password?” link.
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po` — RU UI/messages for reset flow.
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po` — KK UI/messages for reset flow.
- Add tests:
  - `test/edoc_api/password_reset_test.exs`
  - `test/edoc_api_web/controllers/password_reset_controller_test.exs`
  - `test/edoc_api_web/controllers/session_controller_test.exs` (link assertion)

## Chunk 1: Domain + Persistence

### Task 1: Add password reset token schema and migration

**Files:**
- Create: `priv/repo/migrations/20260411120000_create_password_reset_tokens.exs`
- Create: `lib/edoc_api/password_reset_token.ex`
- Test: `test/edoc_api/password_reset_test.exs`

- [ ] **Step 1: Write failing domain tests for token schema + migration guarantees**
  - table exists with required columns
  - unique index on `token_hash`
  - index on `user_id`
  - index on `expires_at`
  - partial active-token index (`used_at IS NULL`)
- [ ] **Step 2: Run domain test file and verify failures**
Run: `mix test test/edoc_api/password_reset_test.exs`
Expected: FAIL (`EdocApi.PasswordReset`/schema missing).
- [ ] **Step 3: Implement migration and schema with indexes**
- [ ] **Step 4: Run migration + tests**
Run: `mix ecto.migrate && mix test test/edoc_api/password_reset_test.exs`
Expected: migration/schema/index tests PASS; remaining failures (if any) are only for unimplemented domain service behavior.
- [ ] **Step 5: Commit**
```bash
git add priv/repo/migrations/20260411120000_create_password_reset_tokens.exs lib/edoc_api/password_reset_token.ex test/edoc_api/password_reset_test.exs
git commit -m "feat: add password reset token schema and migration"
```

### Task 2: Implement `EdocApi.PasswordReset` contracts + concurrency safety

**Files:**
- Create: `lib/edoc_api/password_reset.ex`
- Modify: `lib/edoc_api/accounts.ex`
- Test: `test/edoc_api/password_reset_test.exs`

- [ ] **Step 1: Write failing tests for**
  - `request_reset/3` returns `{:ok, :accepted}` for known/unknown email
  - email is normalized before account lookup
  - known and unknown email paths remain response-identical (anti-enumeration)
  - known-account mailer failure still returns `{:ok, :accepted}`
  - known-account mailer failure writes structured warning log with reset context
  - hashed token stored, raw token not persisted
  - generated raw token meets entropy/length contract (>= 32 random bytes pre-encoding; encoded token length floor assertion)
  - 24h expiry
  - prior active token invalidated on new request
  - `verify_token/1` returns `{:ok, %{user_id: ..., token_hash: ...}}` or `{:error, :invalid_or_expired}`
  - `reset_password/3` updates password + returns `{:ok, :password_reset}`
  - invalid new password payload returns `{:error, :validation_failed, %Ecto.Changeset{}}`
  - used/expired/invalid token returns `{:error, :invalid_or_expired}`
  - concurrent consume: one success, one invalid
  - successful reset revokes all refresh tokens
- [ ] **Step 2: Run domain tests to confirm fail**
Run: `mix test test/edoc_api/password_reset_test.exs`
Expected: FAIL on missing functions/logic.
- [ ] **Step 3: Implement minimal domain logic to satisfy tests**
- [ ] **Step 4: Run domain tests**
Run: `mix test test/edoc_api/password_reset_test.exs`
Expected: PASS.
- [ ] **Step 5: Commit**
```bash
git add lib/edoc_api/password_reset.ex lib/edoc_api/accounts.ex test/edoc_api/password_reset_test.exs
git commit -m "feat: implement password reset domain flow with one-time tokens"
```

### Task 3: Implement request throttling behavior

**Files:**
- Modify: `lib/edoc_api/password_reset.ex`
- Test: `test/edoc_api/password_reset_test.exs`

- [ ] **Step 1: Write failing tests for domain throttling policy**
  - cooldown 60s between sends for same existing user
  - max 3 reset emails/hour for same existing user
  - unknown/nonexistent email is not subject to user-id throttling side effects
  - still returns `{:ok, :accepted}` while suppressing extra sends
- [ ] **Step 2: Run tests and confirm fail**
Run: `mix test test/edoc_api/password_reset_test.exs`
Expected: FAIL on missing throttling/cooldown behavior.
- [ ] **Step 3: Implement throttling based on `password_reset_tokens.inserted_at`**
- [ ] **Step 4: Re-run tests**
Run: `mix test test/edoc_api/password_reset_test.exs`
Expected: PASS.
- [ ] **Step 5: Commit**
```bash
git add lib/edoc_api/password_reset.ex test/edoc_api/password_reset_test.exs
git commit -m "feat: enforce password reset cooldown and hourly cap"
```

## Chunk 2: Web + UI + Localization

### Task 4: Add browser routes and controller flow

**Files:**
- Modify: `lib/edoc_api_web/router.ex`
- Create: `lib/edoc_api_web/controllers/password_reset_controller.ex`
- Create: `lib/edoc_api_web/controllers/password_reset_html.ex`
- Create: `lib/edoc_api_web/controllers/password_reset_html/new.html.heex`
- Create: `lib/edoc_api_web/controllers/password_reset_html/edit.html.heex`
- Test: `test/edoc_api_web/controllers/password_reset_controller_test.exs`

- [ ] **Step 1: Write failing controller tests for**
  - `GET /password/forgot` renders
  - `POST /password/forgot` known/unknown emails return same neutral success message
  - known email path attempts delivery (without leaking this in UI)
  - `GET /password/reset?token=` valid token renders form
  - invalid token path shows localized invalid-link state with CTA back to `/password/forgot`
  - `POST /password/reset` success redirects `/login` with success flash
  - mismatched passwords show localized validation message
- [ ] **Step 2: Run controller tests and confirm fail**
Run: `mix test test/edoc_api_web/controllers/password_reset_controller_test.exs`
Expected: FAIL because routes/controller/templates are not implemented yet.
- [ ] **Step 3: Implement router additions**
  - add forgot/reset browser routes
  - add `password_reset_rate_limit` pipeline (5 req / 60s, `:ip`)
- [ ] **Step 4: Implement controller actions (`new/create/edit/update`)**
- [ ] **Step 5: Implement HEEX templates (`new/edit`)**
- [ ] **Step 6: Re-run controller tests**
Run: `mix test test/edoc_api_web/controllers/password_reset_controller_test.exs`
Expected: PASS.
- [ ] **Step 7: Commit**
```bash
git add lib/edoc_api_web/router.ex lib/edoc_api_web/controllers/password_reset_controller.ex lib/edoc_api_web/controllers/password_reset_html.ex lib/edoc_api_web/controllers/password_reset_html/new.html.heex lib/edoc_api_web/controllers/password_reset_html/edit.html.heex test/edoc_api_web/controllers/password_reset_controller_test.exs
git commit -m "feat: add password reset web flow and routes"
```

### Task 5: Add login-page entry point

**Files:**
- Modify: `lib/edoc_api_web/controllers/session_html/new.html.heex`
- Modify: `test/edoc_api_web/controllers/session_controller_test.exs`

- [ ] **Step 1: Write failing assertion that `/login` includes forgot-password link**
- [ ] **Step 2: Run test and confirm fail**
Run: `mix test test/edoc_api_web/controllers/session_controller_test.exs`
Expected: FAIL because forgot-password link is not yet present.
- [ ] **Step 3: Add always-visible link markup in login template**
- [ ] **Step 4: Re-run test file**
Run: `mix test test/edoc_api_web/controllers/session_controller_test.exs`
Expected: PASS.
- [ ] **Step 5: Commit**
```bash
git add lib/edoc_api_web/controllers/session_html/new.html.heex test/edoc_api_web/controllers/session_controller_test.exs
git commit -m "feat: add forgot-password link to login page"
```

### Task 6: Add localized reset emails + gettext strings

**Files:**
- Modify: `lib/edoc_api/email_sender.ex`
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
- Test: `test/edoc_api/password_reset_test.exs`

- [ ] **Step 1: Write failing tests in `test/edoc_api/password_reset_test.exs` that reset email subject/body is RU/KK and contains reset URL**
  - include translation completeness assertion for reset-flow keys in RU and KK (key parity check against expected key list)
- [ ] **Step 2: Run tests and confirm fail**
Run: `mix test test/edoc_api/password_reset_test.exs`
Expected: FAIL on missing reset-email sender/localization.
- [ ] **Step 3: Implement sender function + RU/KK email/gettext strings**
- [ ] **Step 4: Re-run impacted tests**
Run: `mix test test/edoc_api/password_reset_test.exs test/edoc_api_web/controllers/password_reset_controller_test.exs`
Expected: PASS.
- [ ] **Step 5: Commit**
```bash
git add lib/edoc_api/email_sender.ex priv/gettext/ru/LC_MESSAGES/default.po priv/gettext/kk/LC_MESSAGES/default.po test/edoc_api/password_reset_test.exs test/edoc_api_web/controllers/password_reset_controller_test.exs
git commit -m "feat: localize password reset emails and web messages"
```

## Chunk 3: Verification + Integration

### Task 7: Run focused and full verification suites

**Files:**
- Modify: tests only if regressions found.

- [ ] **Step 1: Run focused auth/reset tests**
Run: `mix test test/edoc_api/password_reset_test.exs test/edoc_api_web/controllers/password_reset_controller_test.exs test/edoc_api_web/controllers/session_controller_test.exs`
Expected: PASS.
- [ ] **Step 2: Run explicit localization checks (RU/KK UI + email content assertions)**
Run: `mix test test/edoc_api/password_reset_test.exs test/edoc_api_web/controllers/password_reset_controller_test.exs`
Expected: PASS on RU/KK message/body assertions.
- [ ] **Step 3: Run full suite**
Run: `mix test`
Expected: PASS. If unrelated known failures remain, record exact failing tests and reason in `docs/superpowers/plans/2026-04-11-password-reset-flow.md` under a `## Verification Notes` section.
- [ ] **Step 4: If failures appear, execute atomic regression loop**
  - add or update failing regression test
  - run targeted test and confirm FAIL
  - implement minimal fix
  - rerun targeted test and confirm PASS
  - rerun focused suite from Step 1
- [ ] **Step 5: Verify no placeholder markers in new reset files**
Run: `rg -n \"TODO|TBD|placeholder\" lib/edoc_api/password_reset.ex lib/edoc_api_web/controllers/password_reset_controller.ex lib/edoc_api_web/controllers/password_reset_html/new.html.heex lib/edoc_api_web/controllers/password_reset_html/edit.html.heex priv/gettext/ru/LC_MESSAGES/default.po priv/gettext/kk/LC_MESSAGES/default.po`
Expected: no matches.
- [ ] **Step 6: Final commit (scoped to password-reset files only)**
```bash
git add lib/edoc_api/password_reset.ex lib/edoc_api/password_reset_token.ex lib/edoc_api/accounts.ex lib/edoc_api/email_sender.ex lib/edoc_api_web/router.ex lib/edoc_api_web/controllers/password_reset_controller.ex lib/edoc_api_web/controllers/password_reset_html.ex lib/edoc_api_web/controllers/password_reset_html/new.html.heex lib/edoc_api_web/controllers/password_reset_html/edit.html.heex lib/edoc_api_web/controllers/session_html/new.html.heex priv/gettext/ru/LC_MESSAGES/default.po priv/gettext/kk/LC_MESSAGES/default.po priv/repo/migrations/20260411120000_create_password_reset_tokens.exs test/edoc_api/password_reset_test.exs test/edoc_api_web/controllers/password_reset_controller_test.exs test/edoc_api_web/controllers/session_controller_test.exs docs/superpowers/plans/2026-04-11-password-reset-flow.md
git commit -m "test: stabilize password reset integration and regressions"
```

### Task 8: Final handoff

- [ ] **Step 1: Write final implementation summary in PR/hand-off note with concrete sections**
  - User-visible flow
  - Security guarantees (neutral response, one-time token, 24h expiry, throttling)
  - Localization coverage (RU/KK)
  - Save this summary under `## Final Handoff Report` section appended to this plan file
- [ ] **Step 2: Include operational commands**
  - `mix ecto.migrate`
  - smoke-check URLs: `/login`, `/password/forgot`, `/password/reset?token=...`
- [ ] **Step 3: Paste exact verification commands and outcomes**
  - focused tests
  - localization tests
  - full `mix test` result (or documented known unrelated failures in `## Verification Notes`)

## Verification Notes

- `mix test test/edoc_api/password_reset_test.exs test/edoc_api_web/controllers/password_reset_controller_test.exs test/edoc_api_web/controllers/session_controller_test.exs` → PASS (`25 tests, 0 failures`)
- `mix test` → PASS (`416 tests, 0 failures`)
- Placeholder scan for new reset-flow files completed during implementation; no TODO/TBD placeholders left in reset files.

## Final Handoff Report

### User-visible flow
- `/login` now shows an always-visible `Forgot your password?` link.
- `/password/forgot` accepts email and always returns neutral success feedback.
- `/password/reset?token=...` supports new-password submission and redirects to `/login` on success.
- Invalid/expired reset links render a recovery state with CTA back to `/password/forgot`.

### Security guarantees
- Reset tokens are generated with strong randomness, hashed before persistence, and expire after 24 hours.
- New reset requests invalidate prior active tokens.
- Token consumption is single-use and atomic on password update.
- Existing-user throttling applies cooldown + hourly cap, while responses remain neutral.
- Successful password reset revokes all active refresh tokens for that user.

### Localization coverage
- Reset UI and flash messages are localized in Russian and Kazakh.
- Password reset emails are localized in Russian and Kazakh and branded as Edocly.
