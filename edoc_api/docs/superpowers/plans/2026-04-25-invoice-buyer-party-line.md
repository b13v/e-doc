# Invoice Buyer Party Line Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the buyer row on `/invoices/:id` and `/invoices/:id/pdf` show a complete legal party line and snapshot buyer legal form/city for direct invoices.

**Architecture:** Add minimal buyer snapshot fields to invoices, populate them in the direct-invoice create/update paths, and centralize invoice buyer-party formatting so the HTML preview and PDF use the same resolution and punctuation rules. Keep backward compatibility by falling back to contract/buyer data for historical invoices without snapshot fields.

**Tech Stack:** Phoenix, HEEx, Ecto migrations/schema changes, invoice service layer in `EdocApi.Invoicing`, ExUnit controller/service tests

---

## File Structure

### Files to create

- `priv/repo/migrations/<timestamp>_add_buyer_snapshot_fields_to_invoices.exs`
  - Adds `buyer_city` and `buyer_legal_form` to `invoices`.

### Files to modify

- `lib/edoc_api/core/invoice.ex`
  - Add schema fields and changeset casting for `buyer_city` and `buyer_legal_form`.
- `lib/edoc_api/invoicing.ex`
  - Populate snapshot fields for direct invoice create/update and expose a shared buyer-party formatter/resolver.
- `lib/edoc_api_web/controllers/invoice_html/show.html.heex`
  - Replace inline buyer-party composition with the shared invoice formatter output.
- `lib/edoc_api_web/pdf_templates.ex`
  - Replace invoice PDF buyer-party inline composition with the same shared formatter output.
- `test/edoc_api_web/controllers/invoices_html_controller_test.exs`
  - Add TDD coverage for direct invoice create behavior and `/invoices/:id` buyer row rendering.
- `test/edoc_api/invoicing/invoice_update_test.exs`
  - Add TDD coverage for refreshing buyer snapshot fields on draft direct invoice update.
- `test/edoc_api_web/controllers/invoice_controller_test.exs`
  - Add PDF rendering regression coverage if this is the established invoice PDF controller test boundary.

### Optional file to modify if existing tests fit better

- `test/edoc_api_web/controllers/workspace_overview_ui_test.exs`
  - Use only if the localized invoice HTML detail page assertions already live here and it is the better home for the buyer-row preview regression.

### Responsibility boundaries

- Snapshot persistence belongs in `EdocApi.Invoicing` and `EdocApi.Core.Invoice`.
- Rendering composition belongs in one invoice-focused helper in `lib/edoc_api/invoicing.ex` unless a nearby invoice presentation module already exists and is clearly a better home.
- Templates should render prepared output, not rebuild buyer-party strings ad hoc.

## Chunk 1: Persist Buyer Snapshot Fields

### Task 1: Add failing tests for direct-invoice snapshot persistence

**Files:**
- Modify: `test/edoc_api_web/controllers/invoices_html_controller_test.exs`
- Modify: `test/edoc_api/invoicing/invoice_update_test.exs`
- Verify against: `lib/edoc_api/invoicing.ex`

- [ ] **Step 1: Add a failing direct-create test for `buyer_city` and `buyer_legal_form`**

Use the existing direct invoice creation test flow and assert the saved invoice contains the selected buyer’s `city` and `legal_form`.

```elixir
test "creates a direct invoice with buyer city and legal form snapshot", %{
  conn: conn,
  user: user,
  buyer: buyer
} do
  conn =
    post(conn, "/invoices", %{
      "invoice" => %{
        "invoice_type" => "direct",
        "buyer_id" => buyer.id,
        ...
      }
    })

  invoice = latest_invoice_for(user.id)

  assert invoice.buyer_city == buyer.city
  assert invoice.buyer_legal_form == buyer.legal_form
end
```

- [ ] **Step 2: Add a failing draft-update test for snapshot refresh**

Extend `test/edoc_api/invoicing/invoice_update_test.exs` so updating a draft direct invoice to a different buyer refreshes `buyer_city` and `buyer_legal_form`.

```elixir
test "update_invoice_for_user/3 refreshes buyer city and legal form for direct invoices" do
  ...
  {:ok, updated} =
    Invoicing.update_invoice_for_user(user.id, invoice.id, %{
      "buyer_id" => buyer_b.id,
      ...
    })

  assert updated.buyer_city == buyer_b.city
  assert updated.buyer_legal_form == buyer_b.legal_form
end
```

- [ ] **Step 3: Run the focused snapshot tests and confirm failure**

Run:

```bash
mix test test/edoc_api_web/controllers/invoices_html_controller_test.exs \
  test/edoc_api/invoicing/invoice_update_test.exs
```

Expected:
- failures because the invoice schema/write path does not yet support the new snapshot fields

- [ ] **Step 4: Add the migration**

Create `priv/repo/migrations/<timestamp>_add_buyer_snapshot_fields_to_invoices.exs`:

```elixir
def change do
  alter table(:invoices) do
    add :buyer_city, :string
    add :buyer_legal_form, :string
  end
end
```

- [ ] **Step 5: Update the invoice schema**

Modify `lib/edoc_api/core/invoice.ex`:

- add `field(:buyer_city, :string)`
- add `field(:buyer_legal_form, :string)`
- include both in cast/normalize logic where appropriate

- [ ] **Step 6: Implement direct-invoice snapshot population**

Modify `lib/edoc_api/invoicing.ex`:

- in direct invoice create flow, resolve selected buyer and merge:
  - `"buyer_city" => buyer.city`
  - `"buyer_legal_form" => buyer.legal_form`
- in draft direct invoice update flow, refresh the same fields when `buyer_id` changes or when direct invoice data is re-resolved
- keep contract invoice behavior unchanged

- [ ] **Step 7: Re-run the focused snapshot tests**

Run:

```bash
mix test test/edoc_api_web/controllers/invoices_html_controller_test.exs \
  test/edoc_api/invoicing/invoice_update_test.exs
```

Expected:
- PASS for the new snapshot assertions

- [ ] **Step 8: Commit the snapshot slice**

```bash
git add priv/repo/migrations/*_add_buyer_snapshot_fields_to_invoices.exs \
  lib/edoc_api/core/invoice.ex \
  lib/edoc_api/invoicing.ex \
  test/edoc_api_web/controllers/invoices_html_controller_test.exs \
  test/edoc_api/invoicing/invoice_update_test.exs
git commit -m "Add buyer snapshot fields to invoices"
```

## Chunk 2: Unify Buyer Party Rendering for HTML and PDF

### Task 2: Prove the current invoice buyer line is incomplete

**Files:**
- Modify: `test/edoc_api_web/controllers/invoices_html_controller_test.exs`
- Modify: `test/edoc_api_web/controllers/invoice_controller_test.exs`
- Verify against: `lib/edoc_api_web/controllers/invoice_html/show.html.heex`
- Verify against: `lib/edoc_api_web/pdf_templates.ex`

- [ ] **Step 1: Add a failing `/invoices/:id` preview test**

Add a test that loads an invoice show page and asserts the buyer row includes:

- BIN/IIN
- legal form
- buyer name
- `Республика Казахстан`
- `г. <city>`
- address

Example assertion shape:

```elixir
assert body =~
  "БИН/ИИН #{invoice.buyer_bin_iin}, #{LegalForms.display(buyer.legal_form)} #{invoice.buyer_name}, Республика Казахстан, г. #{buyer.city}, #{invoice.buyer_address}"
```

- [ ] **Step 2: Add a failing invoice PDF test**

Add or extend invoice PDF test coverage so the PDF HTML source includes the same buyer line. If the PDF controller returns binary PDF only, assert on the HTML builder path or the template-rendered string through the existing PDF test seam used in this codebase.

```elixir
assert html =~
  "БИН/ИИН #{invoice.buyer_bin_iin}, #{LegalForms.display(buyer.legal_form)} #{invoice.buyer_name}, Республика Казахстан, г. #{buyer.city}, #{invoice.buyer_address}"
```

- [ ] **Step 3: Add a failing punctuation regression test**

Cover at least one invoice without buyer city and one invoice without buyer legal form to ensure rendering omits missing fragments without `", ,"` or trailing commas.

```elixir
refute body =~ ", ,"
refute body =~ ", </td>"
```

- [ ] **Step 4: Run the focused rendering tests and confirm failure**

Run:

```bash
mix test test/edoc_api_web/controllers/invoices_html_controller_test.exs \
  test/edoc_api_web/controllers/invoice_controller_test.exs
```

Expected:
- failures showing the current buyer party line is incomplete or inconsistent

- [ ] **Step 5: Introduce one shared invoice buyer-party resolver/formatter**

Modify `lib/edoc_api/invoicing.ex` to add focused helper(s), for example:

```elixir
def invoice_buyer_party_line(invoice) do
  invoice
  |> resolve_invoice_buyer_party()
  |> format_invoice_buyer_party()
end
```

Where resolution priority is:

1. invoice snapshot fields `buyer_legal_form`, `buyer_city`
2. linked contract buyer
3. contract fallback fields if present
4. invoice base fields only

Formatter rules:

- always include `Республика Казахстан`
- include legal form only when present
- include `г. <city>` only when present
- include address only when present
- build text from a filtered list of fragments to avoid dangling commas

- [ ] **Step 6: Replace inline composition in the invoice HTML preview**

Modify `lib/edoc_api_web/controllers/invoice_html/show.html.heex` so the buyer row uses the shared formatter output instead of template-local legal-form/city assembly.

- [ ] **Step 7: Replace inline composition in the invoice PDF template**

Modify `lib/edoc_api_web/pdf_templates.ex` so the invoice PDF buyer row uses the same shared formatter output as the HTML preview.

- [ ] **Step 8: Re-run the focused rendering tests**

Run:

```bash
mix test test/edoc_api_web/controllers/invoices_html_controller_test.exs \
  test/edoc_api_web/controllers/invoice_controller_test.exs
```

Expected:
- PASS for preview, PDF, and punctuation regressions

- [ ] **Step 9: Commit the rendering slice**

```bash
git add lib/edoc_api/invoicing.ex \
  lib/edoc_api_web/controllers/invoice_html/show.html.heex \
  lib/edoc_api_web/pdf_templates.ex \
  test/edoc_api_web/controllers/invoices_html_controller_test.exs \
  test/edoc_api_web/controllers/invoice_controller_test.exs
git commit -m "Unify invoice buyer party rendering"
```

## Chunk 3: Full Verification

### Task 3: Verify the invoice flows end to end

**Files:**
- Verify: `test/edoc_api_web/controllers/invoices_html_controller_test.exs`
- Verify: `test/edoc_api/invoicing/invoice_update_test.exs`
- Verify: `test/edoc_api_web/controllers/invoice_controller_test.exs`

- [ ] **Step 1: Run the invoice-focused test set**

Run:

```bash
mix test test/edoc_api_web/controllers/invoices_html_controller_test.exs \
  test/edoc_api/invoicing/invoice_update_test.exs \
  test/edoc_api_web/controllers/invoice_controller_test.exs
```

Expected:
- all invoice-focused tests PASS

- [ ] **Step 2: Run the full suite**

Run:

```bash
mix test
```

Expected:
- full suite PASS

- [ ] **Step 3: Inspect git diff for scope control**

Run:

```bash
git diff --stat
git diff -- lib/edoc_api/core/invoice.ex lib/edoc_api/invoicing.ex \
  lib/edoc_api_web/controllers/invoice_html/show.html.heex \
  lib/edoc_api_web/pdf_templates.ex \
  test/edoc_api_web/controllers/invoices_html_controller_test.exs \
  test/edoc_api/invoicing/invoice_update_test.exs \
  test/edoc_api_web/controllers/invoice_controller_test.exs
```

Expected:
- only invoice snapshot/rendering files and matching tests changed

- [ ] **Step 4: Commit the verification checkpoint if needed**

```bash
git add -A
git commit -m "Verify invoice buyer party line"
```

Use this only if verification introduced any intentional test/support adjustments that are not already committed.

## Notes for Execution

- Keep the change scoped to invoices only.
- Do not backfill historical invoices in this plan.
- Do not move formatting into an overly generic document helper; keep it invoice-focused unless an obvious existing document-party formatter already exists and matches the responsibility cleanly.
- Prefer filtered fragment lists over nested template conditionals to avoid punctuation bugs.
