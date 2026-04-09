# Verification Email Dedup Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure signup sends at most one automatic verification email, keep resend explicit and rate-limited, and prove the duplicate-email bug is fixed with regression tests.

**Architecture:** Keep `SignupController` as the only automatic sender for browser signup flows, remove the side effect from `VerificationPendingController.new/2`, and keep resend behavior inside `AuthController.resend_verification/2`. Use controller tests plus Swoosh assertions to verify exact mail counts and localized browser responses.

**Tech Stack:** Phoenix, Plug, Ecto, ExUnit, Swoosh test adapter, Gettext

---

## File Map

- Modify: `lib/edoc_api_web/controllers/verification_pending_controller.ex`
  - Remove GET-triggered resend side effect from `/verify-email-pending`.
- Modify: `lib/edoc_api_web/controllers/auth_controller.ex`
  - Keep explicit resend as the only resend path after signup.
  - Surface a browser-friendly localized response for resend success and resend throttling without breaking API anti-enumeration behavior.
- Modify: `lib/edoc_api_web/controllers/verification_pending_html/new.html.heex`
  - Ensure the pending page resend interaction actually renders the resend success/throttle message to the browser user.
- Modify: `test/edoc_api_web/controllers/signup_controller_test.exs`
  - Lock in “exactly one email” behavior for signup and duplicate-email signup.
- Modify: `test/edoc_api_web/controllers/verification_pending_controller_test.exs`
  - Prove pending page load sends no email and preserve existing edge-case branches.
- Modify: `test/edoc_api_web/controllers/auth_controller_test.exs`
  - Prove explicit resend sends once and rate-limited repeat sends none.
- Modify: `priv/gettext/default.pot`
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
  - Add localized browser copy for resend success/throttle messaging if new strings are needed.

## Chunk 1: Lock In the Duplicate-Email Regression

### Task 1: Add failing regression coverage for the duplicate send

**Files:**
- Modify: `test/edoc_api_web/controllers/signup_controller_test.exs`
- Modify: `test/edoc_api_web/controllers/verification_pending_controller_test.exs`

- [ ] **Step 1: Extend signup test to assert exact mail count for fresh signup**

Add or update a controller test so it:
- submits `POST /signup`
- asserts redirect to `/verify-email-pending?email=...`
- asserts exactly one verification email was sent
- optionally confirms the recipient and subject

Example assertion shape:

```elixir
sent =
  Swoosh.Adapters.Local.Storage.Memory.all()
  |> Enum.filter(&verification_email_for?(&1, email))

assert length(sent) == 1
```

- [ ] **Step 2: Extend duplicate-email signup test to assert exact mail count**

Update the existing duplicate-email signup regression so it:
- creates an existing unverified account
- posts duplicate signup
- asserts redirect to `/verify-email-pending?email=...`
- asserts exactly one verification email was sent from the signup submission

- [ ] **Step 3: Add a failing pending-page regression**

In `verification_pending_controller_test.exs`, add a test like:

```elixir
test "pending page load does not send a verification email", %{conn: conn} do
  user = create_user!(%{"email" => "pending@example.com"})

  conn = get(conn, "/verify-email-pending?email=#{URI.encode_www_form(user.email)}")

  assert html_response(conn, 200) =~ user.email

  sent =
    Swoosh.Adapters.Local.Storage.Memory.all()
    |> Enum.filter(&verification_email_for?(&1, user.email))

  assert sent == []
end
```

- [ ] **Step 4: Lock in pending-page edge cases**

Add or preserve explicit tests that confirm:
- missing `email` still redirects to `/signup` with the existing localized flash
- already-verified tokens still redirect correctly through `verify/2`

The goal is to remove only the GET resend side effect, not disturb the existing pending-page UX branches.

- [ ] **Step 5: Run the targeted browser-signup tests to confirm failure**

Run:

```bash
mix test test/edoc_api_web/controllers/signup_controller_test.exs test/edoc_api_web/controllers/verification_pending_controller_test.exs
```

Expected:
- signup exact-count assertions pass or stay green
- pending-page regression fails because `GET /verify-email-pending` currently auto-sends

- [ ] **Step 6: Commit the failing regression slice**

```bash
git add test/edoc_api_web/controllers/signup_controller_test.exs test/edoc_api_web/controllers/verification_pending_controller_test.exs
git commit -m "test: reproduce duplicate verification email sends"
```

## Chunk 2: Remove GET Side Effects and Keep Explicit Resend

### Task 2: Make the pending page read-only

**Files:**
- Modify: `lib/edoc_api_web/controllers/verification_pending_controller.ex`
- Test: `test/edoc_api_web/controllers/verification_pending_controller_test.exs`

- [ ] **Step 1: Remove automatic resend from `VerificationPendingController.new/2`**

Delete the page-load side effect:

```elixir
_ = maybe_resend_verification_email(email, conn.assigns[:locale] || "ru")
```

and remove the now-unused helper if nothing else calls it:

```elixir
defp maybe_resend_verification_email(email, locale) when is_binary(email) do
  ...
end
```

- [ ] **Step 2: Keep rendering behavior unchanged**

`new/2` should still:
- render the page with `email`
- preserve existing page title
- keep existing missing-email behavior

- [ ] **Step 3: Run the pending-page regression**

Run:

```bash
mix test test/edoc_api_web/controllers/verification_pending_controller_test.exs
```

Expected:
- new “does not send” regression passes
- existing verification redirect tests stay green

- [ ] **Step 4: Run the signup regression file**

Run:

```bash
mix test test/edoc_api_web/controllers/signup_controller_test.exs
```

Expected:
- fresh signup still sends exactly one email
- duplicate-email signup still sends exactly one email

- [ ] **Step 5: Commit the controller change**

```bash
git add lib/edoc_api_web/controllers/verification_pending_controller.ex test/edoc_api_web/controllers/verification_pending_controller_test.exs test/edoc_api_web/controllers/signup_controller_test.exs
git commit -m "fix: stop auto-resending verification emails on pending page"
```

## Chunk 3: Rate-Limit Explicit Resend With Clear Browser Feedback

### Task 3: Add resend success/throttle regression tests first

**Files:**
- Modify: `test/edoc_api_web/controllers/auth_controller_test.exs`
- Modify: `lib/edoc_api_web/controllers/verification_pending_html/new.html.heex`

- [ ] **Step 1: Add explicit resend success test**

Add a test that:
- creates an unverified user
- posts once to `/v1/auth/resend-verification`
- asserts one verification email is sent
- asserts the response shape used by the browser remains successful

Suggested command target:

```elixir
conn = post(conn, "/v1/auth/resend-verification", %{"email" => user.email})
assert json_response(conn, 200)["success"] == true
```

- [ ] **Step 2: Add rate-limit regression**

In the same test module:
- post once and assert one mail was sent
- post again immediately
- assert mail count is unchanged
- assert the second response carries the throttle wording expected by the browser path

Example expectation:

```elixir
assert json_response(conn, 200)["message"] =~ "recently requested"
```

- [ ] **Step 3: Inspect the pending-page resend UI contract**

Read `lib/edoc_api_web/controllers/verification_pending_html/new.html.heex` and document how the resend button currently displays server responses:
- whether it relies on HTMX swap targets
- whether it expects JSON or HTML fragments
- whether `success: true/false` affects rendering

Do this before changing the controller response so the browser-visible message is not accidentally dropped.

- [ ] **Step 4: Run the resend tests to confirm current behavior gap**

Run:

```bash
mix test test/edoc_api_web/controllers/auth_controller_test.exs
```

Expected:
- new rate-limit message assertion fails because current behavior returns the same generic success body for both success and throttled resend

- [ ] **Step 5: Commit the failing resend regression**

```bash
git add test/edoc_api_web/controllers/auth_controller_test.exs
git commit -m "test: cover verification resend success and throttling"
```

### Task 4: Implement localized resend feedback

**Files:**
- Modify: `lib/edoc_api_web/controllers/auth_controller.ex`
- Modify: `lib/edoc_api_web/controllers/verification_pending_html/new.html.heex`
- Modify: `priv/gettext/default.pot`
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
- Test: `test/edoc_api_web/controllers/auth_controller_test.exs`

- [ ] **Step 1: Split resend outcomes in `AuthController.resend_verification/2`**

Keep these branches:
- unknown email -> generic anti-enumeration success body
- already verified -> generic anti-enumeration success body
- unverified + allowed -> success body for resend sent
- unverified + rate limited -> throttle body, no new email

Prefer small helpers such as:

```elixir
defp resend_verification_generic_response(conn) do
  json(conn, %{success: true, message: generic_resend_message()})
end

defp resend_verification_sent_response(conn) do
  json(conn, %{success: true, message: gettext("Verification instructions sent. Please check your email.")})
end

defp resend_verification_rate_limited_response(conn) do
  json(conn, %{success: false, message: gettext("You recently requested a verification email. Please wait a moment and try again.")})
end
```

If the browser UI depends on `success: true` for HTMX handling, keep `success: true` and distinguish only by message text. Match the existing client contract instead of forcing a front-end change.

- [ ] **Step 2: Wire the pending-page template to show resend feedback**

Update `verification_pending_html/new.html.heex` as needed so the resend response is visible to the user. Match the existing HTMX/browser pattern already used on this page instead of inventing a new UI contract.

The template change must support:
- visible success feedback after one resend
- visible throttle feedback after an immediate second resend

- [ ] **Step 3: Add localized strings**

Update gettext catalogs for any new resend success or throttle strings introduced in the controller.

- [ ] **Step 4: Run targeted resend tests**

Run:

```bash
mix test test/edoc_api_web/controllers/auth_controller_test.exs
```

Expected:
- resend success test passes
- rate-limit test passes with unchanged mail count

- [ ] **Step 5: Run the combined regression suite**

Run:

```bash
mix test test/edoc_api_web/controllers/signup_controller_test.exs test/edoc_api_web/controllers/verification_pending_controller_test.exs test/edoc_api_web/controllers/auth_controller_test.exs
```

Expected:
- all verification-email regressions pass

- [ ] **Step 6: Commit the resend UX slice**

```bash
git add lib/edoc_api_web/controllers/auth_controller.ex lib/edoc_api_web/controllers/verification_pending_html/new.html.heex priv/gettext/default.pot priv/gettext/ru/LC_MESSAGES/default.po priv/gettext/kk/LC_MESSAGES/default.po test/edoc_api_web/controllers/auth_controller_test.exs
git commit -m "fix: rate limit verification resend with clear feedback"
```

## Chunk 4: End-to-End Verification

### Task 5: Verify the real browser/Swoosh flow manually

**Files:**
- No code changes required

- [ ] **Step 1: Start the dev server if needed**

Run:

```bash
mix phx.server
```

- [ ] **Step 2: Reproduce the user flow manually**

Manual checks:
1. Invite a new member email.
2. Complete signup for that invited email.
3. Confirm redirect to `/verify-email-pending?email=...`.
4. Open `/dev/mailbox` and verify exactly one verification email exists for that address.
5. Click “Resend verification email”.
6. Refresh `/dev/mailbox` and verify exactly one additional verification email appears.
7. Click resend again immediately and verify no third email appears.

- [ ] **Step 3: Record the observed result**

Write down:
- number of messages after signup
- number of messages after one resend
- number of messages after immediate second resend
- browser message shown on the throttled resend

- [ ] **Step 4: Commit if any final copy/test cleanup was needed**

```bash
git add <exact files changed>
git commit -m "test: verify verification email dedup flow"
```

Only do this if the manual QA required a real code change.

## Final Verification

- [ ] Run:

```bash
mix test test/edoc_api_web/controllers/signup_controller_test.exs test/edoc_api_web/controllers/verification_pending_controller_test.exs test/edoc_api_web/controllers/auth_controller_test.exs
```

- [ ] If green, optionally run the broader auth slice:

```bash
mix test test/edoc_api_web/controllers/session_controller_test.exs test/edoc_api_web/controllers/signup_controller_test.exs test/edoc_api_web/controllers/verification_pending_controller_test.exs test/edoc_api_web/controllers/auth_controller_test.exs
```

- [ ] Prepare the final integration commit only after tests and manual mailbox verification are complete.
