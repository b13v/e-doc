# Team Membership Monetization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add seat-limited team membership management so company owners can invite teammates by email from `/company`, see invited and active members, and have invited users automatically activated on login.

**Architecture:** Reuse `tenant_memberships` as the single source of truth for both invited and active tenant members by adding `invite_email` and extending the monetization layer with membership lifecycle functions. Wire the HTML company settings page to this backend, then integrate acceptance into successful login so invited users become active automatically when they authenticate with the invited email.

**Tech Stack:** Elixir, Phoenix, Ecto, PostgreSQL, HEEx, Gettext, ExUnit

---

## File Structure

### Files to Create

- `priv/repo/migrations/20260403090000_add_invite_email_to_tenant_memberships.exs`
- `docs/superpowers/plans/2026-04-03-team-membership-monetization.md`

### Files to Modify

- `lib/edoc_api/core/tenant_membership.ex`
  Responsibility: schema and changeset updates for invited memberships.
- `lib/edoc_api/monetization.ex`
  Responsibility: membership listing, invite, removal, seat counting, and invite acceptance logic.
- `lib/edoc_api/accounts.ex`
  Responsibility: email normalization helper reuse if needed by monetization or auth acceptance.
- `lib/edoc_api_web/controllers/companies_controller.ex`
  Responsibility: render team data and handle invite/remove form posts.
- `lib/edoc_api_web/controllers/companies_html/edit.html.heex`
  Responsibility: Team panel UI with invite form and members list.
- `lib/edoc_api_web/controllers/session_controller.ex`
  Responsibility: accept pending memberships on successful HTML login.
- `lib/edoc_api_web/controllers/auth_controller.ex`
  Responsibility: accept pending memberships on successful API login.
- `lib/edoc_api_web/router.ex`
  Responsibility: add company membership invite/remove routes.
- `priv/gettext/default.pot`
- `priv/gettext/ru/LC_MESSAGES/default.po`
- `priv/gettext/kk/LC_MESSAGES/default.po`
  Responsibility: localization for team-management UI and flash messages.
- `test/edoc_api/monetization_test.exs`
  Responsibility: backend membership lifecycle and seat-count tests.
- `test/edoc_api_web/controllers/companies_controller_test.exs`
  Responsibility: company-page invite/remove flow tests.
- `test/edoc_api_web/controllers/auth_controller_test.exs`
  Responsibility: API login activates invited memberships.
- `test/edoc_api_web/controllers/session_controller_test.exs`
  Responsibility: HTML login activates invited memberships.
- `test/support/fixtures.ex`
  Responsibility: helper functions for creating invited memberships if needed.

### Notes

- Do not add invitation email delivery or acceptance tokens in this plan.
- Keep logic in `Monetization` for this slice instead of introducing a separate team context.
- Count both `invited` and `active` memberships toward seat usage. Exclude `removed`.

## Chunk 1: Data Model And Backend Membership Lifecycle

### Task 1: Add migration for invited memberships

**Files:**
- Create: `priv/repo/migrations/20260403090000_add_invite_email_to_tenant_memberships.exs`
- Modify: `lib/edoc_api/core/tenant_membership.ex`
- Test: `test/edoc_api/monetization_test.exs`

- [ ] **Step 1: Write the failing test**

Add a backend test in `test/edoc_api/monetization_test.exs` that expects invited memberships to persist with normalized `invite_email`, `user_id = nil`, and `status = "invited"`.

```elixir
test "invite_member/2 creates an invited membership with normalized email" do
  user = create_user!()
  company = create_company!(user)

  assert {:ok, membership} =
           Monetization.invite_member(company.id, %{
             "email" => " Teammate@Example.com ",
             "role" => "member"
           })

  assert membership.status == "invited"
  assert membership.user_id == nil
  assert membership.invite_email == "teammate@example.com"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/edoc_api/monetization_test.exs`
Expected: FAIL because `invite_member/2` and/or `invite_email` do not exist yet.

- [ ] **Step 3: Write minimal migration and schema changes**

Implement:

- migration adding nullable `invite_email`
- unique index on `[:company_id, :invite_email]` for non-null invited rows
- schema field `:invite_email`
- changeset rules:
  - allow `user_id` to be nil for invited rows
  - require `invite_email` when `status == "invited"`
  - require `user_id` when `status == "active"`

- [ ] **Step 4: Run test to verify schema compiles but behavior still fails meaningfully**

Run: `mix test test/edoc_api/monetization_test.exs`
Expected: FAIL on undefined backend behavior, not on migration/schema mismatch.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/migrations/20260403090000_add_invite_email_to_tenant_memberships.exs lib/edoc_api/core/tenant_membership.ex test/edoc_api/monetization_test.exs
git commit -m "feat: support invited tenant memberships"
```

### Task 2: Implement invite, list, seat-count, and removal logic

**Files:**
- Modify: `lib/edoc_api/monetization.ex`
- Modify: `test/edoc_api/monetization_test.exs`
- Test: `test/edoc_api/monetization_test.exs`

- [ ] **Step 1: Write the failing tests**

Add tests for:

- seat limit blocks new invite
- duplicate invite is rejected
- active member duplication is rejected
- `subscription_snapshot/1` counts invited memberships as used seats
- removing an invited membership frees the seat
- removing the only owner is rejected

```elixir
test "invite_member/2 rejects invite when all seats are occupied" do
  user = create_user!()
  company = create_company!(user)

  {:ok, _sub} =
    Monetization.activate_subscription_for_company(company.id, %{
      "plan" => "starter",
      "included_seat_limit" => 2
    })

  assert {:ok, _} = Monetization.invite_member(company.id, %{"email" => "one@example.com", "role" => "member"})

  assert {:error, :seat_limit_reached, %{limit: 2}} =
           Monetization.invite_member(company.id, %{"email" => "two@example.com", "role" => "member"})
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/edoc_api/monetization_test.exs`
Expected: FAIL on missing functions or wrong seat counting.

- [ ] **Step 3: Write minimal implementation**

Add to `lib/edoc_api/monetization.ex`:

- `list_memberships/1`
- `invite_member/2`
- `remove_membership/2`
- private helper for occupied seats counting `invited + active`
- owner-removal guard
- shared email normalization using the same strategy as account email normalization

Behavior rules:

- invited email normalized to lowercase trimmed form
- only `admin` and `member` roles allowed for invites
- reject if no seats remain
- reject if email already invited in same company
- reject if user with that email is already active in same company
- remove by setting `status = "removed"` rather than deleting

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/edoc_api/monetization_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/edoc_api/monetization.ex test/edoc_api/monetization_test.exs
git commit -m "feat: add tenant membership invite lifecycle"
```

## Chunk 2: Login-Triggered Membership Activation

### Task 3: Activate invited memberships on successful login

**Files:**
- Modify: `lib/edoc_api/monetization.ex`
- Modify: `lib/edoc_api_web/controllers/auth_controller.ex`
- Modify: `lib/edoc_api_web/controllers/session_controller.ex`
- Modify: `test/edoc_api_web/controllers/auth_controller_test.exs`
- Create: `test/edoc_api_web/controllers/session_controller_test.exs`
- Test: `test/edoc_api_web/controllers/auth_controller_test.exs`
- Test: `test/edoc_api_web/controllers/session_controller_test.exs`

- [ ] **Step 1: Write the failing API login test**

Add to `test/edoc_api_web/controllers/auth_controller_test.exs`:

```elixir
test "successful login activates invited memberships" do
  owner = create_user!()
  Accounts.mark_email_verified!(owner.id)
  company = create_company!(owner)

  invited = create_user!(%{"email" => "invitee@example.com"})
  Accounts.mark_email_verified!(invited.id)

  assert {:ok, _membership} =
           EdocApi.Monetization.invite_member(company.id, %{
             "email" => invited.email,
             "role" => "member"
           })

  conn =
    build_conn()
    |> post("/v1/auth/login", %{"email" => invited.email, "password" => "password123"})

  assert conn.status == 200
  assert Companies.get_company_by_user_id(invited.id).id == company.id
end
```

- [ ] **Step 2: Write the failing HTML login test**

Create `test/edoc_api_web/controllers/session_controller_test.exs` with:

```elixir
test "html login activates invited memberships", %{conn: conn} do
  owner = create_user!()
  Accounts.mark_email_verified!(owner.id)
  company = create_company!(owner)

  invited = create_user!(%{"email" => "invitee2@example.com"})
  Accounts.mark_email_verified!(invited.id)

  assert {:ok, _membership} =
           EdocApi.Monetization.invite_member(company.id, %{
             "email" => invited.email,
             "role" => "member"
           })

  conn =
    conn
    |> Plug.Test.init_test_session(%{})
    |> post("/login", %{"email" => invited.email, "password" => "password123"})

  assert redirected_to(conn) == "/company"
  assert get_session(conn, :user_id) == invited.id
  assert Companies.get_company_by_user_id(invited.id).id == company.id
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

- `mix test test/edoc_api_web/controllers/auth_controller_test.exs`
- `mix test test/edoc_api_web/controllers/session_controller_test.exs`

Expected: FAIL because acceptance is not wired after login.

- [ ] **Step 4: Write minimal implementation**

Implement `accept_pending_memberships_for_user/1` in `Monetization`:

- find invited memberships by normalized email
- bind `user_id`
- clear or preserve `invite_email` consistently; prefer preserving for traceability unless the schema or uniqueness gets in the way
- set `status = "active"`

Call the helper:

- after successful verified API login in `AuthController.login/2`
- after successful verified HTML login in `SessionController.create/2`

- [ ] **Step 5: Run tests to verify they pass**

Run:

- `mix test test/edoc_api_web/controllers/auth_controller_test.exs`
- `mix test test/edoc_api_web/controllers/session_controller_test.exs`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/edoc_api/monetization.ex lib/edoc_api_web/controllers/auth_controller.ex lib/edoc_api_web/controllers/session_controller.ex test/edoc_api_web/controllers/auth_controller_test.exs test/edoc_api_web/controllers/session_controller_test.exs
git commit -m "feat: activate invited memberships on login"
```

## Chunk 3: Company Settings Team Management UI

### Task 4: Render team panel and member list on `/company`

**Files:**
- Modify: `lib/edoc_api_web/controllers/companies_controller.ex`
- Modify: `lib/edoc_api_web/controllers/companies_html/edit.html.heex`
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs`
- Test: `test/edoc_api_web/controllers/companies_controller_test.exs`

- [ ] **Step 1: Write the failing render test**

Add a test that expects:

- invite form on `/company`
- role selector
- team list
- owner row visible

```elixir
test "renders team management panel on company settings", %{conn: conn, company: company} do
  body =
    conn
    |> get("/company")
    |> html_response(200)

  assert body =~ ~s(action="/company/memberships")
  assert body =~ "team[email]"
  assert body =~ "team[role]"
  assert body =~ company.name
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/edoc_api_web/controllers/companies_controller_test.exs`
Expected: FAIL because the team panel does not exist.

- [ ] **Step 3: Write minimal implementation**

Update `CompaniesController.edit/2` to assign `memberships = Monetization.list_memberships(company.id)`.

Update `edit.html.heex` to render:

- Team section below subscription
- invite form posting to `/company/memberships`
- members table with:
  - email (`invite_email` fallback to active user email)
  - role
  - status
  - remove button when allowed

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/edoc_api_web/controllers/companies_controller_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/edoc_api_web/controllers/companies_controller.ex lib/edoc_api_web/controllers/companies_html/edit.html.heex test/edoc_api_web/controllers/companies_controller_test.exs
git commit -m "feat: add company team management panel"
```

### Task 5: Implement invite and remove member form handlers

**Files:**
- Modify: `lib/edoc_api_web/router.ex`
- Modify: `lib/edoc_api_web/controllers/companies_controller.ex`
- Modify: `lib/edoc_api_web/controllers/companies_html/edit.html.heex`
- Modify: `priv/gettext/default.pot`
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
- Modify: `test/edoc_api_web/controllers/companies_controller_test.exs`
- Test: `test/edoc_api_web/controllers/companies_controller_test.exs`

- [ ] **Step 1: Write the failing invite/remove tests**

Add controller tests for:

- posting invite creates invited membership and redirects to `/company`
- duplicate invite shows localized error flash
- deleting invited membership marks it removed and frees seat
- owner row has no remove action or backend rejects removal

```elixir
test "invites a member from company settings", %{conn: conn, company: company} do
  conn =
    post(conn, "/company/memberships", %{
      "team" => %{"email" => "member@example.com", "role" => "member"}
    })

  assert redirected_to(conn) == "/company"
  assert Enum.any?(EdocApi.Monetization.list_memberships(company.id), &(&1.invite_email == "member@example.com"))
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/edoc_api_web/controllers/companies_controller_test.exs`
Expected: FAIL because routes and handlers do not exist.

- [ ] **Step 3: Write minimal implementation**

Add routes:

- `post("/company/memberships", CompaniesController, :invite_member)`
- `delete("/company/memberships/:id", CompaniesController, :remove_member)`

Add controller actions:

- `invite_member/2`
- `remove_member/2`

Both actions should:

- resolve current company from current user
- call monetization layer
- redirect back to `/company`
- show localized flash

Localization keys to add:

- invite sent / team member invited
- member removed
- seat limit reached
- member already invited
- member already active
- invalid email
- cannot remove last owner
- invite failed generic

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/edoc_api_web/controllers/companies_controller_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/edoc_api_web/router.ex lib/edoc_api_web/controllers/companies_controller.ex lib/edoc_api_web/controllers/companies_html/edit.html.heex priv/gettext/default.pot priv/gettext/ru/LC_MESSAGES/default.po priv/gettext/kk/LC_MESSAGES/default.po test/edoc_api_web/controllers/companies_controller_test.exs
git commit -m "feat: add company member invite and removal flows"
```

## Chunk 4: Verification And Cleanup

### Task 6: Add fixture helpers only if tests are too noisy

**Files:**
- Modify: `test/support/fixtures.ex`
- Test: any touched suite

- [ ] **Step 1: Add helper only if repetition is blocking clarity**

Possible helpers:

- `invite_company_member!(company, attrs \\ %{})`
- `list_company_membership_emails(company)`

Keep helpers minimal and avoid hiding assertions.

- [ ] **Step 2: Run focused tests**

Run:

- `mix test test/edoc_api/monetization_test.exs`
- `mix test test/edoc_api_web/controllers/companies_controller_test.exs`
- `mix test test/edoc_api_web/controllers/auth_controller_test.exs`
- `mix test test/edoc_api_web/controllers/session_controller_test.exs`

Expected: PASS

- [ ] **Step 3: Commit if helper added**

```bash
git add test/support/fixtures.ex test/edoc_api/monetization_test.exs test/edoc_api_web/controllers/companies_controller_test.exs test/edoc_api_web/controllers/auth_controller_test.exs test/edoc_api_web/controllers/session_controller_test.exs
git commit -m "test: streamline team membership fixtures"
```

### Task 7: Run full verification before completion

**Files:**
- No code changes required unless regressions appear

- [ ] **Step 1: Run full suite**

Run: `mix test`
Expected: `0 failures`

- [ ] **Step 2: Run formatter if needed**

Run: `mix format`
Expected: no diff or only formatting diff

- [ ] **Step 3: Re-run affected tests if formatting touched files**

Run:

- `mix test test/edoc_api/monetization_test.exs`
- `mix test test/edoc_api_web/controllers/companies_controller_test.exs`
- `mix test test/edoc_api_web/controllers/auth_controller_test.exs`
- `mix test test/edoc_api_web/controllers/session_controller_test.exs`

- [ ] **Step 4: Final commit**

If verification fixes were needed:

```bash
git add .
git commit -m "chore: finalize team membership monetization flow"
```

## Execution Notes

- Follow strict TDD: every behavior change starts with a failing test.
- Do not build email delivery or acceptance links in this plan.
- Keep routes and UI under `/company`; do not create a separate team settings page.
- Preserve the current company resolution behavior in `Companies.get_company_by_user_id/1`.
- Use localized RU/KK flashes and labels for any new team-management copy.
- Leave `.worktrees/` untracked and out of commits.
