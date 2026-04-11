# Password Reset Design (Login → Forgot Password)

Date: 2026-04-11  
Status: Approved for planning

## 1. Goal

Add a secure, localized password reset flow so users who forgot their password can recover access from the login page.

Required product decisions:
- "Forgot password?" link is always visible on `/login`
- Forgot-password submit returns neutral success text (no account enumeration)
- Reset token lifetime is 24 hours
- After successful reset, redirect to `/login` with success flash
- Reset requests are rate-limited

## 2. Scope

In scope:
- UI entry point from `/login`
- Forgot-password request page and submit endpoint
- Reset form page and password update endpoint
- Token issuance, validation, one-time use, expiry
- Localized RU/KK UI strings and email content
- Rate limiting for reset requests
- Tests for happy path and security edge cases

Out of scope:
- Passwordless login
- SMS/WhatsApp reset
- Admin-triggered password reset

## 3. User Flow

1. User opens `/login` and sees "Forgot password?" link.
2. User opens `/password/forgot`.
3. User submits email.
4. System always responds with neutral success message.
5. If account exists, system sends reset email with secure link.
6. User opens `/password/reset?token=...`.
7. User sets new password and confirmation.
8. On success: password is updated, token is consumed, active refresh sessions are revoked, user is redirected to `/login` with localized success flash.

## 4. Architecture and Units

## 4.1 Web layer

Add `PasswordResetController` with:
- `new/2` (`GET /password/forgot`)
- `create/2` (`POST /password/forgot`)
- `edit/2` (`GET /password/reset`)
- `update/2` (`POST /password/reset`)

Templates:
- `password_reset_html/new.html.heex` (email request form)
- `password_reset_html/edit.html.heex` (new password form)

Router additions under browser pipeline:
- `get "/password/forgot", PasswordResetController, :new`
- `post "/password/forgot", PasswordResetController, :create`
- `get "/password/reset", PasswordResetController, :edit`
- `post "/password/reset", PasswordResetController, :update`

Login page update:
- Add always-visible link to `/password/forgot`.

## 4.2 Domain layer

Add `EdocApi.PasswordReset` context module:
- `request_reset(email, locale, meta \\ %{})`
- `verify_token(token)`
- `reset_password(token, password, confirmation)`

Public contracts:
- `request_reset/3 :: {:ok, :accepted}`  
  Notes: always returns `{:ok, :accepted}` to callers for neutral UX, regardless of account existence, throttling, or mailer failure.
- `verify_token/1 :: {:ok, %{user_id: binary(), token_hash: binary()}} | {:error, :invalid_or_expired}`
- `reset_password/3 :: {:ok, :password_reset} | {:error, :invalid_or_expired} | {:error, :validation_failed, Ecto.Changeset.t()}`

Responsibilities:
- Normalize email
- Apply per-user cooldown policy for existing accounts
- Generate secure token, store hash only
- Invalidate previous active reset tokens for the user
- Send localized reset email (if user exists)
- Enforce one-time token consumption
- Enforce expiry (24h)
- Update password through `Accounts`/`User` changeset path
- Revoke refresh tokens after successful reset via `Accounts.revoke_all_refresh_tokens/1` (new function)

## 4.3 Persistence

New table: `password_reset_tokens`
- `id` (uuid)
- `user_id` (fk users, on_delete: :delete_all)
- `token_hash` (unique)
- `expires_at` (utc_datetime)
- `used_at` (utc_datetime, nullable)
- timestamps

Indexes:
- unique index on `token_hash`
- index on `user_id`
- index on `expires_at`
- partial index on active tokens (`used_at IS NULL`) for efficient active-token checks

## 4.4 Email integration

Extend `EdocApi.EmailSender`:
- `send_password_reset_email(recipient_email, token, locale \\ "ru")`
- RU/KK subject/body variants with Edocly branding
- Reset URL: `${BASE_URL}/password/reset?token=...`

Delivery semantics:
- Keep current app pattern: synchronous `Mailer.deliver/1` inside request path.
- If delivery fails, log error with structured context; do not change caller response (still neutral success).
- No background queue in this slice (keeps scope aligned with current architecture).

## 5. Security Model

- No account existence disclosure in `/password/forgot` response.
- Store only hashed token in DB.
- Use strong random token (>= 32 bytes entropy before encoding).
- Token validity: 24h.
- Token is one-time use (`used_at` set atomically).
- Older active reset tokens for same user are invalidated on new request.
- Password update path preserves existing password policy.
- Revoke refresh tokens upon successful password reset.

Concurrency rule:
- `reset_password/3` must consume token with single-winner semantics inside DB transaction:
  - `UPDATE ... SET used_at = now() WHERE token_hash = ? AND used_at IS NULL AND expires_at > now()`
  - exactly one updated row is required; otherwise return `{:error, :invalid_or_expired}`.

## 6. Rate Limiting

Two layers:
1. HTTP/IP layer: plug-level rate limit for `POST /password/forgot` at `5 requests / 60 seconds` (subject `:ip`).
2. Domain layer (for existing users only, keyed by `user_id`):
  - cooldown: minimum `60 seconds` between reset-email sends
  - cap: maximum `3 reset emails / rolling 1 hour`
  - counters derived from `password_reset_tokens.inserted_at` (no new counter store)

Behavior:
- Response to caller stays neutral even when throttled.
- Internal status can be logged/telemetry-only for observability.

## 7. Localization

All new strings localized in RU/KK:
- Login link text
- Forgot/reset form labels and hints
- Success/error flashes
- Token invalid/expired messages
- Email subjects and bodies

Localization policy for this slice:
- Every new reset-flow key must have RU and KK translations in repo.
- Missing key fallback technically follows gettext defaults, but tests will treat missing RU/KK keys as failure for reset-flow strings.

## 8. Error Handling

Forgot request (`create`):
- Always returns same success UI message.

Reset page (`edit`):
- Missing/invalid/expired/used token shows localized invalid-link state with CTA back to forgot page.

Reset submit (`update`):
- Password validation errors shown inline/localized (including confirmation mismatch).
- Invalid/expired/used token yields localized error and blocks reset.

## 9. Testing Strategy (TDD-first)

Create failing tests first, then implement:

Controller/UI tests:
- `/login` includes forgot-password link.
- `/password/forgot` renders.
- Submit known email returns neutral success and attempts email delivery.
- Submit unknown email returns same neutral success and does not reveal account state.
- `/password/reset` with valid token renders reset form.
- `/password/reset` invalid/expired/used token is rejected with localized message.
- Successful reset redirects to `/login` with localized success flash.

Domain tests:
- Token created with 24h expiry.
- Raw token is never persisted.
- New request invalidates prior active tokens.
- One-time use enforced.
- Rate limit/cooldown policy enforced.
- Successful reset revokes refresh tokens.

Localization tests:
- RU and KK reset email subject/body.
- RU and KK flashes/messages for reset flow.

## 10. Rollout Notes

- Backward compatible: adds new routes and table; existing login path unchanged.
- No migration impact on existing auth tables.
- Feature can be released behind standard deploy/migrate flow.
