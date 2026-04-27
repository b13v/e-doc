# Admin Billing Client Layout Refactor Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `/admin/billing/clients/:id` so the company title includes the short legal form, `Company Info` uses labeled fields, and `Invoice History`, `Submitted payments`, and `Payment History` are rendered as tables without changing billing behavior.

**Architecture:** Keep the change local to the admin billing presentation layer. Reproduce the current layout issues with controller-level HTML assertions first, then refactor `client.html.heex` to reuse the existing `company_display_name/1` helper, replace the unlabeled company sentence with a small labeled grid, and convert the three history sections from freeform blocks into semantic tables while preserving the recent dark-mode hook pattern.

**Tech Stack:** Phoenix, HEEx templates, ExUnit, Tailwind utility classes

---

## File Structure

- Modify: `lib/edoc_api_web/controllers/admin_billing_html/client.html.heex`
  - Owns the admin client detail UI for `/admin/billing/clients/:id`.
  - Will be refactored to use the short legal-form title, labeled company info, and table-based invoice/payment sections.
- Modify: `lib/edoc_api_web/controllers/admin_billing_html.ex`
  - Already owns `company_display_name/1`, `invoice_plan_label/1`, `date_or_dash/1`, and related helpers.
  - May need small display helpers for table cell formatting if the template would otherwise become repetitive.
- Modify: `lib/edoc_api_web/components/layouts.ex`
  - Owns explicit dark-mode override hooks for admin billing pages.
  - Only touch if new table heading/label hook classes are required for runtime dark-mode contrast.
- Modify: `test/edoc_api_web/controllers/admin_billing_controller_test.exs`
  - Owns controller-level regressions for admin billing pages.
  - Will gain failing assertions for the current admin client detail layout, then pass once the template is refactored.

## Chunk 1: Reproduce the Layout Gaps

### Task 1: Add failing controller coverage for the current admin client detail layout

**Files:**
- Modify: `test/edoc_api_web/controllers/admin_billing_controller_test.exs`

- [ ] **Step 1: Extend the existing client-detail test with layout assertions that fail on the current page**

Add assertions near the existing `/admin/billing/clients/:id` coverage so the test expects:

- the page title to contain the short legal form (`ТОО Backoffice Client`)
- `Company Info` to contain labeled fields (`БИН/ИИН`, `Email`, `Телефон`)
- table headers for `Invoice History`
- table headers for `Submitted payments`
- table headers for `Payment History`

Suggested assertion shape:

```elixir
assert body =~ "ТОО Backoffice Client"
assert body =~ "БИН/ИИН"
assert body =~ "Email"
assert body =~ "Телефон"
assert body =~ "Invoice number"
assert body =~ "Submitted at"
assert body =~ "Created at"
```

Keep the assertions specific to this page so the test proves the structure, not just generic text presence.

- [ ] **Step 2: Run the focused controller test to verify it fails**

Run:

```bash
mix test test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Expected:
- FAIL because the current page still renders:
  - bare company name in the title
  - a dot-separated unlabeled company info sentence
  - freeform blocks instead of history/payment table headers

## Chunk 2: Title and Company Info Refactor

### Task 2: Refactor the top of the page to use existing display helpers and labeled metadata

**Files:**
- Modify: `lib/edoc_api_web/controllers/admin_billing_html/client.html.heex`
- Modify: `lib/edoc_api_web/controllers/admin_billing_html.ex` (only if helper extraction reduces duplication cleanly)
- Test: `test/edoc_api_web/controllers/admin_billing_controller_test.exs`

- [ ] **Step 3: Replace the bare company title with the existing short legal-form display helper**

In the page header, replace:

```heex
<%= @client.company.name %>
```

with:

```heex
<%= company_display_name(@client.company) %>
```

Do not introduce a second legal-form formatting implementation in the template.

- [ ] **Step 4: Replace the dot-separated `Company Info` sentence with labeled fields**

Refactor the `Company Info` section from:

```heex
<p class="mt-2 text-sm text-gray-700 dark:text-slate-200">
  <%= @client.company.bin_iin %> · <%= @client.company.email %> · <%= @client.company.phone %>
</p>
```

to a responsive labeled layout such as:

```heex
<dl class="mt-4 grid gap-4 md:grid-cols-3">
  <div>
    <dt class="text-xs font-semibold uppercase text-stone-500 dark:text-white">БИН/ИИН</dt>
    <dd class="mt-1 text-sm font-semibold text-gray-900 dark:text-slate-100"><%= value_or_dash(@client.company.bin_iin) %></dd>
  </div>
  <div>
    <dt class="text-xs font-semibold uppercase text-stone-500 dark:text-white">Email</dt>
    <dd class="mt-1 text-sm font-semibold text-gray-900 dark:text-slate-100"><%= value_or_dash(@client.company.email) %></dd>
  </div>
  <div>
    <dt class="text-xs font-semibold uppercase text-stone-500 dark:text-white">Телефон</dt>
    <dd class="mt-1 text-sm font-semibold text-gray-900 dark:text-slate-100"><%= value_or_dash(@client.company.phone) %></dd>
  </div>
</dl>
```

Use `value_or_dash/1` for safety so missing values do not render blank layout holes.

## Chunk 3: Table-ize Invoice and Payment Sections

### Task 3: Convert history and submitted-payment sections to semantic tables

**Files:**
- Modify: `lib/edoc_api_web/controllers/admin_billing_html/client.html.heex`
- Modify: `lib/edoc_api_web/controllers/admin_billing_html.ex` (only if a helper is needed for concise cell formatting)
- Modify: `lib/edoc_api_web/components/layouts.ex` (only if runtime dark-mode hook selectors are needed for new table headings/cells)
- Test: `test/edoc_api_web/controllers/admin_billing_controller_test.exs`

- [ ] **Step 5: Convert `Invoice History` from freeform blocks to a table**

Replace the loop of `div.admin-billing-client-history-text` invoice blocks with a table using columns:

- `Invoice number`
- `Status`
- `Tariff`
- `Amount`
- `Due date`

Suggested structure:

```heex
<table class="mt-4 min-w-full divide-y divide-stone-200 dark:divide-slate-800">
  <thead>
    <tr>
      <th class="admin-billing-client-table-heading ...">Invoice number</th>
      <th class="admin-billing-client-table-heading ...">Status</th>
      <th class="admin-billing-client-table-heading ...">Tariff</th>
      <th class="admin-billing-client-table-heading ...">Amount</th>
      <th class="admin-billing-client-table-heading ...">Due date</th>
    </tr>
  </thead>
  <tbody>
    <%= for invoice <- @client.invoices do %>
      <tr>
        <td class="admin-billing-client-history-text ..."><%= invoice.id %></td>
        <td class="admin-billing-client-history-text ..."><%= invoice.status %></td>
        <td class="admin-billing-client-history-text ..."><%= invoice_plan_label(invoice) %></td>
        <td class="admin-billing-client-history-text ..."><%= invoice.amount_kzt %> KZT</td>
        <td class="admin-billing-client-history-text ..."><%= date_or_dash(invoice.due_at) %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

- [ ] **Step 6: Convert `Submitted payments` from cards to a table**

Render a table with columns:

- `Payment`
- `Invoice number`
- `Invoice status`
- `Payment status`
- `Method`
- `Amount`
- `Reference`
- `Submitted at`

Keep optional data in-row:

- show proof URL in the payment/reference cell or a dedicated details cell
- show review note in the same row without expanding into a second card layout

If the template becomes repetitive, add a small formatting helper in `admin_billing_html.ex` instead of embedding more conditional string logic in the HEEx.

- [ ] **Step 7: Convert `Payment History` from freeform blocks to a table**

Render columns:

- `Payment`
- `Status`
- `Method`
- `Amount`
- `Created at`

Use the existing `date_or_dash/1` helper for the date/timestamp column.

## Chunk 4: Preserve Dark-Mode Readability

### Task 4: Keep the recent dark-mode fix intact after the structural refactor

**Files:**
- Modify: `lib/edoc_api_web/controllers/admin_billing_html/client.html.heex`
- Modify: `lib/edoc_api_web/components/layouts.ex` (only if new runtime hooks are required)
- Test: `test/edoc_api_web/controllers/admin_billing_controller_test.exs`

- [ ] **Step 8: Apply the existing admin billing hook pattern to any new table headings or labels**

If the new table structure introduces headings or labels that rely on runtime dark-mode overrides, add explicit hook classes such as:

```heex
<th class="admin-billing-client-table-heading ...">Invoice number</th>
```

and, only if needed, add matching selectors in `layouts.ex`:

```css
html[data-theme="dark"] .admin-billing-client-table-heading {
  color: #ffffff !important;
  opacity: 1 !important;
}
```

Do not add layout-level CSS unless the template-only classes are insufficient in this app’s runtime theme system.

## Chunk 5: Verify and Commit

### Task 5: Prove the layout refactor works and does not regress the admin billing page

**Files:**
- Modify: `lib/edoc_api_web/controllers/admin_billing_html/client.html.heex`
- Modify: `lib/edoc_api_web/controllers/admin_billing_html.ex` (if helper changes were needed)
- Modify: `lib/edoc_api_web/components/layouts.ex` (if hook changes were needed)
- Modify: `test/edoc_api_web/controllers/admin_billing_controller_test.exs`

- [ ] **Step 9: Run the focused admin billing controller test to verify it passes**

Run:

```bash
mix test test/edoc_api_web/controllers/admin_billing_controller_test.exs
```

Expected:
- PASS

- [ ] **Step 10: Run the full test suite**

Run:

```bash
mix test
```

Expected:
- PASS

- [ ] **Step 11: Commit the refactor**

Run:

```bash
git add lib/edoc_api_web/controllers/admin_billing_html/client.html.heex lib/edoc_api_web/controllers/admin_billing_html.ex lib/edoc_api_web/components/layouts.ex test/edoc_api_web/controllers/admin_billing_controller_test.exs
git commit -m "Refactor admin billing client detail layout"
```

Only include helper/layout changes if they were actually required by the implementation.
