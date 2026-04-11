# Verification Resend Rate-Limit Localization Design

Date: 2026-04-11
Status: Draft for review
Owner: Web/Auth

## 1. Context

On `/verify-email-pending?email=...`, when the user clicks **Resend verification email** too quickly, the UI displays:

- `Please wait before requesting another verification email.`

This appears in English and does not meet localization requirements for Russian/Kazakh UI.

## 2. Goal

Replace the current rate-limit response text with a user-friendly, localized message in:

- Russian (`ru`)
- Kazakh (`kk`)

The behavior and throttling logic stay unchanged; only the displayed message contract is updated.

## 3. Scope

In scope:

- Update the `:rate_limited` response message key used by resend-verification API flow.
- Add/ensure Russian and Kazakh translations for the new user-friendly message.
- Update tests asserting rate-limit message payload.

Out of scope:

- Changing resend throttling rules (cooldown/window).
- Changing HTTP status codes or API shape.
- Visual redesign of `/verify-email-pending` UI.

## 4. Recommended Approach (Approved Option 2)

Introduce a new gettext message for the rate-limited state (instead of reusing old English phrasing), then wire that message into the existing response path.

Why:

- Keeps old string history isolated.
- Avoids semantic coupling with legacy wording.
- Makes future text edits safer and explicit.

## 5. Functional Design

### 5.1 Response behavior

When resend request hits rate limit:

- API returns the same JSON structure as today:
  - `success: true`
  - `status: "rate_limited"`
  - `message: <localized user-friendly text>`
- Only `message` content changes.

### 5.2 Localized message content

Use user-friendly message meaning:

- RU: wait before trying resend again.
- KK: same meaning in Kazakh.

Exact wording will be defined in gettext entries and validated by tests.

### 5.3 UI behavior

`/verify-email-pending` keeps current HTMX rendering logic.
No JS behavior change is required because it already displays `payload.message`.

## 6. Units and Boundaries

### Unit A: Auth resend response mapping

- File area: `AuthController` resend message helper.
- Responsibility: map resend statuses to localized message text.
- Interface: internal helper returning translated string for `:rate_limited`.

### Unit B: Localization catalog

- File area: `priv/gettext/{ru,kk}/LC_MESSAGES/default.po` (+ template sync).
- Responsibility: provide translations for new message key.
- Interface: gettext lookup by msgid.

### Unit C: Controller/API tests

- File area: auth controller resend tests.
- Responsibility: assert localized rate-limit response text contract.
- Interface: test assertions on JSON payload.

## 7. Error Handling and Edge Cases

- Unknown email remains generic response; unchanged.
- Resend success response text remains unchanged.
- If locale is missing/invalid, existing locale fallback behavior remains unchanged.

## 8. Testing Strategy

Required:

1. Existing resend-verification controller test for rate-limit case updated to expect new localized message.
2. Run targeted controller tests for resend flow.
3. Run full test suite if touched gettext extraction introduces cross-test expectations.

## 9. Risks and Mitigations

- Risk: tests fail due to hardcoded old English string.
  - Mitigation: update explicit assertions for new message.
- Risk: translation key added only in one locale.
  - Mitigation: update both `ru` and `kk` catalogs in same change.

## 10. Acceptance Criteria

1. On rate-limited resend from `/verify-email-pending`, user sees Russian text in `ru` locale.
2. On rate-limited resend from `/verify-email-pending`, user sees Kazakh text in `kk` locale.
3. English message `Please wait before requesting another verification email.` is no longer used for `:rate_limited` in localized UI flow.
4. Relevant tests pass.

