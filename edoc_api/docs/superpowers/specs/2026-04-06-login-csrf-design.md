# Login CSRF Recovery Design

Date: 2026-04-06
Status: Proposed

## Problem

The browser flow `verify email -> redirect to /login -> submit login form` can fail with `Plug.CSRFProtection.InvalidCSRFTokenError` before the normal login logic runs. In the reported case, the user submits a wrong password after verifying their email and sees a raw CSRF exception instead of the expected invalid-credentials message.

The current login form already renders a hidden `_csrf_token`, and `/login` is behind the browser pipeline with `fetch_session` and `protect_from_forgery`. That means the likely failure mode is not missing CSRF plumbing; it is a session/token mismatch in a real browser flow.

## Goal

Preserve CSRF protection while making the browser auth flow resilient and user-friendly.

Success criteria:

- Invalid CSRF on `POST /login` does not surface as a raw exception page.
- The user is redirected back to `/login` with a localized flash message instructing them to retry.
- The email verification success path reduces the chance of session/token mismatch before the login page is shown.
- Normal login failures with a valid CSRF token still show the current invalid-credentials message.

## Non-Goals

- No weakening or disabling of Phoenix CSRF protection.
- No JavaScript-only workaround as the primary fix.
- No changes to API auth endpoints under `/v1`.

## Recommended Approach

Implement two server-side protections together:

1. Add centralized recovery for browser-side CSRF failures on auth pages.
2. Renew the session on successful email verification before redirecting to `/login`.

This keeps the security model intact and fixes the user-facing failure mode even if a browser presents a stale page or token.

## Approach Options Considered

### Option A: Central CSRF recovery only

Catch `Plug.CSRFProtection.InvalidCSRFTokenError` for browser auth requests and redirect back to `/login` with a localized flash such as "The page expired, please try again."

Pros:

- Minimal and robust.
- Preserves CSRF protection.
- Fixes the raw exception UX.

Cons:

- Handles the symptom at the boundary but does not reduce the likelihood of mismatch in the verify-email flow.

### Option B: Session renew on verification only

After successful email verification, renew the browser session and then redirect to `/login`.

Pros:

- Targets the suspicious transition point directly.

Cons:

- Not sufficient by itself. Any future stale-form scenario can still raise the same exception.

### Option C: Combined recovery plus session renew

Use Option A as the user-facing safety net and Option B as a hardening step on the verification success path.

Pros:

- Best reliability.
- Keeps behavior predictable for all browser auth forms.
- Limits future regressions from similar session transitions.

Cons:

- Slightly more implementation work than either single option.

Recommendation: Option C.

## Design

### 1. Browser CSRF failure handling

Introduce a browser-oriented recovery path for `Plug.CSRFProtection.InvalidCSRFTokenError`.

Expected behavior:

- For `POST /login`, redirect to `/login`.
- Attach a localized flash explaining that the page expired and should be retried.
- Avoid exposing the raw exception page to end users in this auth flow.

Preferred implementation shape:

- Handle the exception at the endpoint level where browser request context and session are available.
- Keep the behavior scoped to HTML browser routes. JSON/API routes should continue using their current behavior.

### 2. Verification success hardening

When `/verify-email?token=...` succeeds:

- renew the browser session;
- then redirect to `/login`.

This reduces the chance that an old session/CSRF state survives across the verification boundary.

### 3. Localization

Add a user-facing flash message for CSRF expiry in Russian and Kazakh through the existing gettext flow.

The message should be short and action-oriented. Example intent:

- Russian: "Сессия страницы истекла. Попробуйте войти снова."
- Kazakh: equivalent meaning.

Exact copy can be finalized during implementation.

## Data Flow

### Valid login request

1. User loads `/login`.
2. Browser receives session cookie and CSRF token.
3. User submits form with valid `_csrf_token`.
4. `SessionController.create/2` runs.
5. Wrong password results in the existing invalid-credentials flash.

### Stale or invalid login request

1. User submits `/login` with stale or mismatched `_csrf_token`.
2. Phoenix rejects the request during forgery protection.
3. The new browser CSRF recovery path catches the failure.
4. User is redirected to `/login` with a localized "retry" flash.

## Error Handling

- Unknown or invalid verification token behavior remains unchanged.
- API auth endpoints keep current responses and should not be redirected into browser pages.
- CSRF recovery must not swallow unrelated exceptions.

## Testing Plan

Add regression coverage for:

1. `POST /login` with invalid CSRF token redirects to `/login` with a flash instead of raising.
2. `GET /verify-email?token=...` success still redirects to `/login`.
3. A normal wrong-password login from a valid login page continues to show the invalid-credentials message.
4. Localized flash text appears in Russian and Kazakh for the CSRF recovery path.

## Risks

- Catching CSRF exceptions too broadly could affect routes outside auth. The implementation should scope recovery to browser HTML requests intentionally.
- Session renewal on verification should not clear unrelated flash state that the flow relies on. Tests should verify the final redirect behavior.

## Rollout

- Implement server-side recovery and verification session hardening.
- Run targeted controller tests first, then broader auth/browser tests.
- Verify manually in the browser with the reported flow:
  `verify email -> redirected /login -> wrong password -> friendly flash, no exception`.
