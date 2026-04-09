# Login CSRF Recovery Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent raw `Plug.CSRFProtection.InvalidCSRFTokenError` failures on browser login and recover with a localized redirect while preserving normal invalid-credentials behavior.

**Architecture:** Add a focused browser-side CSRF recovery path around the endpoint/request pipeline so stale login submissions redirect cleanly to `/login`, then harden the verification success flow by renewing the session before redirecting to login. Keep API behavior unchanged and prove the fix with targeted controller and endpoint-level tests.

**Tech Stack:** Phoenix 1.7, Plug CSRF protection, gettext localization, ExUnit/Phoenix ConnCase

---

## File Map

- Modify: `lib/edoc_api_web/endpoint.ex`
  - Add scoped browser recovery for invalid CSRF on auth pages.
- Modify: `lib/edoc_api_web/controllers/verification_pending_controller.ex`
  - Renew session on successful email verification before redirecting to `/login`.
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
  - Add Russian translation for CSRF recovery flash.
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
  - Add Kazakh translation for CSRF recovery flash.
- Modify: `test/edoc_api_web/controllers/session_controller_test.exs`
  - Add failing login CSRF regression coverage and preserve wrong-password behavior.
- Modify: `test/edoc_api_web/controllers/verification_pending_controller_test.exs`
  - Add verification success regression around redirect/session hardening if needed.

## Chunk 1: Login CSRF Recovery

### Task 1: Add failing browser CSRF regression test

**Files:**
- Modify: `test/edoc_api_web/controllers/session_controller_test.exs`

- [ ] **Step 1: Write the failing test**

Add a test that posts to `/login` with an invalid `_csrf_token` through the browser pipeline and expects a redirect to `/login` with a flash instead of an exception.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
mix test test/edoc_api_web/controllers/session_controller_test.exs
```

Expected: FAIL due to `Plug.CSRFProtection.InvalidCSRFTokenError` or missing redirect behavior.

- [ ] **Step 3: Write minimal recovery implementation**

Implement a scoped recovery path in `lib/edoc_api_web/endpoint.ex` that catches `Plug.CSRFProtection.InvalidCSRFTokenError` for HTML browser auth submissions and redirects to `/login` with a localized flash.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
mix test test/edoc_api_web/controllers/session_controller_test.exs
```

Expected: PASS, with CSRF failures redirecting cleanly.

- [ ] **Step 5: Commit**

```bash
git add lib/edoc_api_web/endpoint.ex test/edoc_api_web/controllers/session_controller_test.exs
git commit -m "fix: recover browser login from invalid csrf"
```

## Chunk 2: Verification Flow Hardening

### Task 2: Add failing verification-flow regression

**Files:**
- Modify: `test/edoc_api_web/controllers/verification_pending_controller_test.exs`
- Modify: `test/edoc_api_web/controllers/session_controller_test.exs`

- [ ] **Step 1: Write the failing test**

Add a regression that verifies successful `/verify-email` still redirects to `/login` and then a stale or mismatched subsequent login submission recovers through the CSRF redirect path rather than crashing.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
mix test test/edoc_api_web/controllers/verification_pending_controller_test.exs test/edoc_api_web/controllers/session_controller_test.exs
```

Expected: FAIL before session-renew hardening is added.

- [ ] **Step 3: Write minimal implementation**

Update `lib/edoc_api_web/controllers/verification_pending_controller.ex` to renew the browser session on successful verification before redirecting to `/login`.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
mix test test/edoc_api_web/controllers/verification_pending_controller_test.exs test/edoc_api_web/controllers/session_controller_test.exs
```

Expected: PASS, with verification redirect preserved and session state renewed.

- [ ] **Step 5: Commit**

```bash
git add lib/edoc_api_web/controllers/verification_pending_controller.ex test/edoc_api_web/controllers/verification_pending_controller_test.exs test/edoc_api_web/controllers/session_controller_test.exs
git commit -m "fix: renew session after email verification"
```

## Chunk 3: Localization and Safety Checks

### Task 3: Localize the recovery message and verify unchanged wrong-password flow

**Files:**
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
- Modify: `test/edoc_api_web/controllers/session_controller_test.exs`

- [ ] **Step 1: Write the failing assertions**

Extend tests to assert the CSRF recovery flash is localized and that a normal wrong-password login from a valid form still shows the existing invalid-credentials message.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
mix test test/edoc_api_web/controllers/session_controller_test.exs
```

Expected: FAIL on missing localized copy or wrong flow behavior.

- [ ] **Step 3: Write minimal implementation**

Add gettext entries for the recovery flash and wire the endpoint/controller recovery path to use them.

- [ ] **Step 4: Run targeted and broader auth tests**

Run:

```bash
mix test test/edoc_api_web/controllers/session_controller_test.exs test/edoc_api_web/controllers/verification_pending_controller_test.exs test/edoc_api_web/controllers/auth_controller_test.exs
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add priv/gettext/ru/LC_MESSAGES/default.po priv/gettext/kk/LC_MESSAGES/default.po test/edoc_api_web/controllers/session_controller_test.exs
git commit -m "fix: localize login csrf recovery flow"
```

## Execution Notes

- Follow TDD strictly: each regression test must fail before the corresponding implementation change.
- Keep CSRF recovery scoped to browser HTML auth flows. Do not change `/v1` API behavior.
- Avoid broad exception swallowing; recover only `Plug.CSRFProtection.InvalidCSRFTokenError`.
- Preserve the existing invalid-credentials flow for valid CSRF submissions.

## Verification Checklist

- `POST /login` with invalid CSRF redirects to `/login` with a localized flash.
- `GET /verify-email?token=...` still redirects to `/login`.
- Wrong password from a valid login form still renders the current invalid-credentials message.
- No API auth tests regress.

Plan complete and saved to `docs/superpowers/plans/2026-04-06-login-csrf-recovery.md`. Ready to execute.
