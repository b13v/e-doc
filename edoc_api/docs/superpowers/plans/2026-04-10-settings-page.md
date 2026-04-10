# Settings Page Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add authenticated `/settings` page where a user can update first name, surname, and password; make clicking the navbar email open this page.

**Architecture:** Extend `users` with profile fields (`first_name`, `last_name`), add account update APIs in `EdocApi.Accounts`, and expose HTML settings flows through a new `SettingsController`. Use two independent forms on one page (`profile` and `password`) to keep validation/errors isolated and predictable.

**Tech Stack:** Phoenix 1.7 controllers/templates, Ecto changesets/migrations, Gettext, ExUnit/Phoenix.ConnTest.

---

## File Structure (Responsibilities)

- Create: `priv/repo/migrations/<timestamp>_add_profile_fields_to_users.exs`
- Modify: `lib/edoc_api/accounts/user.ex`
  - Add schema fields and dedicated changesets for profile/password updates.
- Modify: `lib/edoc_api/accounts.ex`
  - Add user-facing account update functions with validation and persistence.
- Create: `lib/edoc_api_web/controllers/settings_controller.ex`
  - HTTP handlers for rendering settings and processing profile/password updates.
- Create: `lib/edoc_api_web/controllers/settings_html.ex`
- Create: `lib/edoc_api_web/controllers/settings_html/edit.html.heex`
  - Settings page UI with two forms and flash/errors.
- Modify: `lib/edoc_api_web/router.ex`
  - Add authenticated settings routes.
- Modify: `lib/edoc_api_web/components/layouts.ex`
  - Make email in authenticated navbar route to `/settings` (desktop + mobile).
- Create: `test/edoc_api_web/controllers/settings_controller_test.exs`
  - End-to-end controller coverage for both update flows.
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
- Modify: `priv/gettext/en/LC_MESSAGES/default.po`
  - Add settings labels/messages.

---

## Chunk 1: Domain + Data Layer

### Task 1: Add user profile fields

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_profile_fields_to_users.exs`
- Test: `test/edoc_api_web/controllers/settings_controller_test.exs` (uses persisted fields)

- [ ] **Step 1: Write failing test for persisted profile fields via settings update**
```elixir
test "PUT /settings/profile persists first_name and last_name", %{conn: conn} do
  # create verified user, login session, submit profile form
  # assert redirect and DB values changed
end
```

- [ ] **Step 2: Run test to verify it fails**
Run: `mix test test/edoc_api_web/controllers/settings_controller_test.exs:1 -v`  
Expected: FAIL (unknown route/controller or missing fields).

- [ ] **Step 3: Add migration**
Create nullable `:first_name` and `:last_name` string columns on `users`.

- [ ] **Step 4: Run migration + targeted test**
Run: `mix ecto.migrate && mix test test/edoc_api_web/controllers/settings_controller_test.exs:1 -v`  
Expected: still FAIL (app layer not implemented yet), but DB schema is ready.

- [ ] **Step 5: Commit**
```bash
git add priv/repo/migrations
git commit -m "db: add first_name and last_name to users"
```

### Task 2: Add account changesets and update APIs

**Files:**
- Modify: `lib/edoc_api/accounts/user.ex`
- Modify: `lib/edoc_api/accounts.ex`
- Test: `test/edoc_api_web/controllers/settings_controller_test.exs`

- [ ] **Step 1: Write failing tests for profile/password behavior**
```elixir
test "PUT /settings/password rejects wrong current password"
test "PUT /settings/password updates hash when current password is valid"
```

- [ ] **Step 2: Run tests to verify failures**
Run: `mix test test/edoc_api_web/controllers/settings_controller_test.exs -v`  
Expected: FAIL on missing account update functions/flows.

- [ ] **Step 3: Implement minimal domain code**
- In `User` schema:
  - add `field :first_name, :string`
  - add `field :last_name, :string`
  - add `profile_changeset/2` with length trims/validation.
  - add `password_update_changeset/2` with same password rules as registration (`min: 8, max: 72`) and hashing.
- In `Accounts` context:
  - add `update_user_profile(user_id, attrs)`
  - add `update_user_password(user_id, current_password, new_password, confirmation)`
  - enforce `current_password` verification via `Argon2.verify_pass/2`.

- [ ] **Step 4: Re-run tests**
Run: `mix test test/edoc_api_web/controllers/settings_controller_test.exs -v`  
Expected: still partial FAIL until web layer/routes/templates are added.

- [ ] **Step 5: Commit**
```bash
git add lib/edoc_api/accounts.ex lib/edoc_api/accounts/user.ex
git commit -m "feat(accounts): support user profile and password updates"
```

---

## Chunk 2: Web Layer + UX

### Task 3: Add settings routes and controller actions

**Files:**
- Modify: `lib/edoc_api_web/router.ex`
- Create: `lib/edoc_api_web/controllers/settings_controller.ex`
- Create: `lib/edoc_api_web/controllers/settings_html.ex`
- Create: `lib/edoc_api_web/controllers/settings_html/edit.html.heex`
- Test: `test/edoc_api_web/controllers/settings_controller_test.exs`

- [ ] **Step 1: Write failing route/controller tests**
```elixir
test "GET /settings renders settings page for authenticated user"
test "PUT /settings/profile updates profile and redirects with flash"
test "PUT /settings/password updates password and redirects with flash"
test "unauthenticated /settings redirects to /login"
```

- [ ] **Step 2: Run tests to verify failures**
Run: `mix test test/edoc_api_web/controllers/settings_controller_test.exs -v`  
Expected: FAIL on missing routes/controller/template.

- [ ] **Step 3: Implement minimal web flow**
- Add routes inside `:auth_browser` scope:
  - `get "/settings", SettingsController, :edit`
  - `put "/settings/profile", SettingsController, :update_profile`
  - `put "/settings/password", SettingsController, :update_password`
- Build settings template with:
  - profile form: `first_name`, `last_name`
  - password form: `current_password`, `password`, `password_confirmation`
  - CSRF + method override + translated labels
  - user-friendly flash and inline errors.

- [ ] **Step 4: Re-run tests**
Run: `mix test test/edoc_api_web/controllers/settings_controller_test.exs -v`  
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/edoc_api_web/router.ex lib/edoc_api_web/controllers/settings_controller.ex lib/edoc_api_web/controllers/settings_html.ex lib/edoc_api_web/controllers/settings_html/edit.html.heex test/edoc_api_web/controllers/settings_controller_test.exs
git commit -m "feat(web): add authenticated settings page for profile and password"
```

### Task 4: Make navbar email open `/settings`

**Files:**
- Modify: `lib/edoc_api_web/components/layouts.ex`
- Test: `test/edoc_api_web/controllers/settings_controller_test.exs`

- [ ] **Step 1: Write failing UI assertion test**
```elixir
test "authenticated layout links account email to /settings"
```

- [ ] **Step 2: Run test to verify failure**
Run: `mix test test/edoc_api_web/controllers/settings_controller_test.exs -v`  
Expected: FAIL because email is plain text today.

- [ ] **Step 3: Implement minimal navbar changes**
- Desktop auth navbar: render account email as `<a href="/settings">...`.
- Mobile auth menu: add a visible settings link near account section.
- Keep current theme/dark-mode classes consistent.

- [ ] **Step 4: Re-run test**
Run: `mix test test/edoc_api_web/controllers/settings_controller_test.exs -v`  
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/edoc_api_web/components/layouts.ex test/edoc_api_web/controllers/settings_controller_test.exs
git commit -m "feat(nav): route account email to settings page"
```

---

## Chunk 3: Localization + Verification

### Task 5: Add gettext entries for settings copy

**Files:**
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
- Modify: `priv/gettext/en/LC_MESSAGES/default.po`
- Test: `test/edoc_api_web/controllers/settings_controller_test.exs`

- [ ] **Step 1: Write failing localization assertions**
```elixir
test "settings page uses localized labels and flashes"
```

- [ ] **Step 2: Run test to verify failure**
Run: `mix test test/edoc_api_web/controllers/settings_controller_test.exs -v`  
Expected: FAIL on untranslated strings.

- [ ] **Step 3: Add translation keys**
- Page/title/form labels: settings, first name, surname, change password, current password, new password, confirm password.
- Flashes: profile updated, password updated, invalid current password, password validation errors.

- [ ] **Step 4: Re-run settings tests**
Run: `mix test test/edoc_api_web/controllers/settings_controller_test.exs -v`  
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add priv/gettext/en/LC_MESSAGES/default.po priv/gettext/ru/LC_MESSAGES/default.po priv/gettext/kk/LC_MESSAGES/default.po test/edoc_api_web/controllers/settings_controller_test.exs
git commit -m "i18n: localize settings page and account update messages"
```

### Task 6: Full regression verification

**Files:**
- Test: `test/edoc_api_web/controllers/settings_controller_test.exs`
- Test: existing auth/workspace tests that touch layout/session

- [ ] **Step 1: Run focused regression suite**
Run:
```bash
mix test test/edoc_api_web/controllers/settings_controller_test.exs \
  test/edoc_api_web/controllers/session_controller_test.exs \
  test/edoc_api_web/controllers/signup_controller_test.exs \
  test/edoc_api_web/controllers/workspace_overview_ui_test.exs
```
Expected: PASS.

- [ ] **Step 2: Run full suite**
Run: `mix test`  
Expected: PASS (no regressions).

- [ ] **Step 3: Final commit**
```bash
git add .
git commit -m "feat: add user settings page with profile and password management"
```

