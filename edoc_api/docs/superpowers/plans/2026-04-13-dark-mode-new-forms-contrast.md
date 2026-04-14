# Dark-Mode Contrast Fix For New Invoice/Act Forms Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix dark-mode readability on `/invoices/new` and `/acts/new` for mode toggles and item areas, including JS-generated item rows.

**Architecture:** Keep the fix template-local and class-based. First lock behavior with server-rendered regression tests in `workspace_overview_ui_test.exs`, then apply minimal Tailwind `dark:*` class updates in both templates and dynamic `addItemRow()` markup strings. Verify with targeted tests and full workspace UI test file.

**Tech Stack:** Phoenix HEEx templates, Tailwind utility classes, ExUnit controller HTML tests.

---

## File map

- Modify: `test/edoc_api_web/controllers/workspace_overview_ui_test.exs`
- Modify: `lib/edoc_api_web/controllers/invoice_html/new.html.heex`
- Modify: `lib/edoc_api_web/controllers/act_html/new.html.heex`
- Reference spec: `docs/superpowers/specs/2026-04-13-dark-mode-new-forms-contrast-design.md`

---

## Chunk 1: Lock Regression Coverage (TDD first)

### Task 1: Add failing regression test for dark-mode class contracts

**Files:**
- Modify: `test/edoc_api_web/controllers/workspace_overview_ui_test.exs`

- [ ] **Step 1: Add one focused regression test for both pages and both modes**
  - Fixtures for deterministic rendering:
    - verified user + company
    - at least one buyer for both invoice/act routes
    - at least one bank account for invoice routes
    - at least one signed contract for `invoice_type=contract` and `act_type=contract` routes
  - Add/extend test to render:
    - `/invoices/new?invoice_type=direct`
    - `/invoices/new?invoice_type=contract`
    - `/acts/new?act_type=direct`
    - `/acts/new?act_type=contract`
  - Assert class-token contracts (scoped to relevant regions) for:
    - mode toggle container: `dark:border-slate-600`, `dark:bg-slate-800/80`
    - mode labels: `dark:text-slate-100`
    - item heading: `dark:text-slate-100`
    - item surface: `dark:bg-slate-900/80`
    - dynamic row template in script: `dark:text-slate-300`, `dark:bg-slate-800`, `dark:text-slate-100`, `dark:ring-slate-600`
  - Assert parity (token-level):
    - static form-control dark class groups are also present in `addItemRow()` template strings for labels/inputs/selects on both pages

- [ ] **Step 2: Run test to confirm it fails before implementation**
  - Run: `mix test test/edoc_api_web/controllers/workspace_overview_ui_test.exs`
  - Expected: FAIL with missing dark-mode tokens on `/invoices/new` and/or `/acts/new`.

- [ ] **Step 3: Commit test-only change**
  - `git add test/edoc_api_web/controllers/workspace_overview_ui_test.exs`
  - `git commit -m "test(ui): add dark-mode contrast regression for invoice/act new forms"`

---

## Chunk 2: Implement Invoice New Dark-Mode Fix

### Task 2: Add missing dark classes in invoice new template

**Files:**
- Modify: `lib/edoc_api_web/controllers/invoice_html/new.html.heex`
- Test: `test/edoc_api_web/controllers/workspace_overview_ui_test.exs`

- [ ] **Step 1: Update mode toggle contrast**
  - In toggle card wrapping `#invoice_type_contract` and `#invoice_type_direct`:
    - add `dark:border-slate-600 dark:bg-slate-800/80`
  - In radio labels:
    - add `dark:text-slate-100`

- [ ] **Step 2: Update item block contrast**
  - In invoice items heading:
    - add `dark:text-slate-100`
  - In wrapper containing `#items-container`:
    - add `dark:bg-slate-900/80`

- [ ] **Step 3: Update `addItemRow()` dynamic template**
  - For label/input/select classes in generated rows:
    - include `dark:text-slate-300` for labels
    - include `dark:bg-slate-800 dark:text-slate-100 dark:ring-slate-600` for controls

- [ ] **Step 4: Run tests for invoice path**
  - Run: `mix test test/edoc_api_web/controllers/workspace_overview_ui_test.exs`
  - Expected: invoice-side assertions pass; if act-side still fails, proceed to Chunk 3.

- [ ] **Step 5: Commit invoice template changes**
  - `git add lib/edoc_api_web/controllers/invoice_html/new.html.heex`
  - `git commit -m "fix(ui): improve dark-mode contrast on invoice new form"`

---

## Chunk 3: Implement Act New Dark-Mode Fix

### Task 3: Add missing dark classes in act new template and dynamic rows

**Files:**
- Modify: `lib/edoc_api_web/controllers/act_html/new.html.heex`
- Test: `test/edoc_api_web/controllers/workspace_overview_ui_test.exs`

- [ ] **Step 1: Update mode toggle contrast**
  - In toggle card wrapping `#act_type_contract` and `#act_type_direct`:
    - add `dark:border-slate-600 dark:bg-slate-800/80`
  - In radio labels:
    - add `dark:text-slate-100`

- [ ] **Step 2: Update item block contrast**
  - In items heading:
    - add `dark:text-slate-100`
  - In wrapper containing `#items-container`:
    - add `dark:bg-slate-900/80`

- [ ] **Step 3: Update `addItemRow()` dynamic markup**
  - In generated row HTML string:
    - labels include `dark:text-slate-300`
    - inputs/selects include `dark:bg-slate-800 dark:text-slate-100 dark:ring-slate-600`
  - Keep name attributes and row-index behavior unchanged.

- [ ] **Step 4: Run tests**
  - Run: `mix test test/edoc_api_web/controllers/workspace_overview_ui_test.exs`
  - Expected: full file PASS.

- [ ] **Step 5: Commit act template changes**
  - `git add lib/edoc_api_web/controllers/act_html/new.html.heex`
  - `git commit -m "fix(ui): improve dark-mode contrast on act new form and dynamic rows"`

---

## Chunk 4: Final Verification And Cleanup

### Task 4: Validate no regressions and finish

**Files:**
- Verify: `test/edoc_api_web/controllers/workspace_overview_ui_test.exs`
- Verify: touched templates in invoice/act new pages

- [ ] **Step 1: Run focused verification**
  - Run:
    - `mix test test/edoc_api_web/controllers/workspace_overview_ui_test.exs`
  - Expected: PASS.
  - If this fails: stop and investigate before staging/commit steps.

- [ ] **Step 2: Run broader safety check (optional)**
  - Run:
    - `mix test test/edoc_api_web/controllers/core_ui_localization_test.exs`
  - Expected: PASS (optional safety check; no localization regressions from class-only changes).
  - If this fails: stop and investigate before final commit.

- [ ] **Step 3: Inspect git diff for scope**
  - Run:
    - `git diff --name-only HEAD`
    - `git diff --cached --name-only`
    - `CHANGED_ALL=$( { git diff --name-only HEAD; git diff --cached --name-only; } | sort -u )`
    - `printf "%s\n" "$CHANGED_ALL" | grep -Ev '^(test/edoc_api_web/controllers/workspace_overview_ui_test.exs|lib/edoc_api_web/controllers/invoice_html/new.html.heex|lib/edoc_api_web/controllers/act_html/new.html.heex)$' > /tmp/dark_mode_scope_violations.txt || true`
    - `cat /tmp/dark_mode_scope_violations.txt`
  - Expected:
    - `/tmp/dark_mode_scope_violations.txt` is empty
    - any non-empty output means scope violation; stop and investigate.
    - working tree/staging contains only 0 or the 3 scoped files for this plan.

- [ ] **Step 4: Final commit (if needed)**
  - Decision rule:
    - if Chunk 2 and Chunk 3 commits were already created: skip this step (no extra consolidation commit)
    - if implementation was intentionally done as a single-commit strategy: stage only the 3 scoped files and create one commit here:
      - `git commit -m "chore(ui): finalize dark-mode contrast regression and template parity"`
  - Expected:
    - no duplicate/extra commit when Chunk 2/3 already committed
    - exactly one scoped commit only when using single-commit strategy.

---

## Execution notes

- Keep changes DRY and strictly class-level (YAGNI): no new components/helpers unless unavoidable.
- Follow @superpowers/test-driven-development and @superpowers/verification-before-completion while implementing.
- If tests become brittle due to class ordering, assert stable class tokens or scoped regex instead of full exact class attribute strings.
