# Verification Email Dedup Design

## Problem

Users who complete signup are redirected to `/verify-email-pending?email=...`.

Today the system can send two verification emails for the same signup:

- `POST /signup` sends or resends a verification email.
- `GET /verify-email-pending` also auto-resends a verification email on page load.

Because both paths mint a fresh token, Swoosh shows two near-identical verification emails with different tokens. This is incorrect. The system should send one verification email automatically, and only send another one when the user explicitly clicks the resend button.

## Goals

- Ensure signup produces at most one automatic verification email per explicit submission.
- Preserve the existing verification email after a normal fresh signup.
- Keep explicit resend available from the pending page.
- Rate-limit resend requests so repeated clicks do not spam emails.
- Return clear, localized user feedback for both successful resend and rate-limited resend attempts.

## Non-Goals

- Changing verification token format or expiry policy.
- Changing invitation email behavior.
- Changing API anti-enumeration behavior for resend beyond localized browser UX.

## Recommended Approach

Use signup as the single automatic sender and make the pending page read-only.

### Why

- Signup is the actual state-changing action and the correct place to send the first verification email.
- GET page loads should not trigger email side effects. Refresh, duplicate tabs, browser prefetch, and back/forward cache can all re-trigger them.
- This gives a clear product rule: one automatic email on signup, more emails only on explicit resend.

## Behavior Design

### Signup flow

- `POST /signup` continues to send one verification email for newly created users.
- If signup hits an existing unverified account on the duplicate-email path, signup may resend one verification email as part of that explicit submission.
- After either path, the browser redirects to `/verify-email-pending?email=...`.

### Verification pending page

- `GET /verify-email-pending` renders status only.
- It must not enqueue or send verification emails on page load.
- Refreshing the page must not create a new token or email.

### Explicit resend flow

- The resend button remains the only way to request another verification email from the pending page.
- Resend continues to use the existing resend endpoint and resend policy.
- On allowed resend, the user sees the normal localized success message confirming that verification instructions were sent.
- On rate-limited resend, no email is sent and the user sees a localized throttle message telling them to wait briefly before trying again.

## Controller Changes

### `SignupController`

- Keep the current email send for fresh registration.
- Keep the existing unverified-account resend path on duplicate signup, because it is tied to an explicit user action.
- No deduplication state is needed here once the pending page stops auto-sending.

### `VerificationPendingController`

- Remove the automatic resend side effect from `new/2`.
- Keep the page focused on display and verification redirect behavior only.

### `AuthController`

- Keep resend logic behind the explicit resend endpoint.
- Improve the browser-facing response so rate-limited resend can surface a localized message instead of looking identical to a successful resend.
- Preserve anti-enumeration behavior where applicable for API consumers.

## UX and Messaging

Browser messages should be localized in Russian and Kazakh.

Required browser outcomes:

- Successful resend: existing “verification instructions sent” style message.
- Rate-limited resend: friendly message such as “You recently requested a verification email. Please wait a moment and try again.”

The pending page should continue to behave correctly even if the email address is missing or already verified.

## Testing Strategy

Add regression tests first, then fix implementation.

Required tests:

1. Signup sends exactly one verification email for a fresh invited-user signup.
2. Duplicate-email signup for an existing unverified account sends exactly one verification email.
3. Loading `/verify-email-pending?email=...` sends no verification email.
4. Clicking resend from the pending page sends one additional verification email when allowed.
5. Re-clicking resend inside the rate-limit window does not send another email and returns the localized throttle message.

Tests should verify mail count, not just presence of any message, so token duplication is caught directly.

## Risks

- If the signup send fails and the user does not click resend, there is no automatic recovery from the pending page anymore. This is acceptable because GET-triggered side effects are the bigger correctness problem, and the resend button remains available.
- If resend messaging changes for browser flows, existing API tests may need small adjustments to distinguish HTML UX from API anti-enumeration behavior.

## Rollout

- Land regression tests with the controller changes in one slice.
- Verify locally with Swoosh mailbox that signup now creates one email and resend creates the second only after the button click.
