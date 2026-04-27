# Admin Billing Client Page Layout Refactor

## Problem

The admin billing client detail page at `/admin/billing/clients/:id` still has several layout and information-presentation issues:

- the company title shows only the company name and omits the legal form
- the `Company Info` section renders BIN/IIN, email, and phone as one unlabeled sentence
- `Invoice History`, `Submitted payments`, and `Payment History` are rendered as freeform blocks instead of structured tables

The page works, but it is harder to scan than it should be for backoffice operations.

## Goals

- Show the company title with the short legal form before the company name.
- Make `Company Info` clearly labeled and easier to read.
- Convert the three history sections into table-based layouts with visible column headers.
- Preserve the current billing workflows and data sources.
- Keep dark-mode readability intact while changing the structure.

## Non-Goals

- No changes to billing behavior, actions, routes, or permissions.
- No new billing fields or schema changes.
- No localization refactor in this task.
- No redesign of unrelated admin billing pages.

## Recommended Approach

Use the existing admin billing helper layer and refactor the page template into a more structured presentation:

- reuse the existing short legal-form company display helper for the title
- replace the unlabeled company sentence with labeled rows
- replace the freeform billing history cards with semantic tables

This keeps the change local to the admin detail page and follows patterns already used on the admin billing list pages.

## Design

### 1. Company Title

The top page heading should use the short legal form before the company name:

- `ТОО Backoffice Client`
- `АО Example Company`
- `ИП Example Founder`

The short form is sufficient here. The full legal form is not needed in the title.

### 2. Company Info

The `Company Info` pane should stop using a dot-separated plain text line.

Instead, render labeled fields such as:

- `БИН/ИИН: <value>`
- `Email: <value>`
- `Телефон: <value>`

This should be presented as a simple responsive grid so the labels and values are visually paired.

### 3. Invoice History Table

Replace the current freeform invoice blocks with a table.

Recommended columns:

- `Invoice number`
- `Status`
- `Tariff`
- `Amount`
- `Due date`

The table should remain compact and optimized for scanability.

### 4. Submitted Payments Table

Replace the current payment detail cards with a table.

Recommended columns:

- `Payment`
- `Invoice number`
- `Invoice status`
- `Payment status`
- `Method`
- `Amount`
- `Reference`
- `Submitted at`

Optional fields such as proof URL and review note can stay inside the row in a dedicated cell so the table does not become excessively wide.

### 5. Payment History Table

Replace the current freeform payment history blocks with a table.

Recommended columns:

- `Payment`
- `Status`
- `Method`
- `Amount`
- `Created at`

### 6. Dark-Mode Compatibility

The recent dark-mode contrast fix must continue to hold after the structural changes.

Any new table headings, labels, and row cells introduced by this refactor should use the same explicit high-contrast dark-mode hook pattern already used on this page.

## Testing

Add controller coverage for `/admin/billing/clients/:id` that asserts:

- the title includes the short legal form
- `Company Info` renders labeled fields
- `Invoice History` renders table headers
- `Submitted payments` renders table headers
- `Payment History` renders table headers
- the dark-mode hook classes continue to appear for the new structured elements

Verification should include:

- focused admin billing controller tests
- full `mix test`

## Acceptance Criteria

- The company title shows short legal form plus company name.
- `Company Info` shows labeled BIN/IIN, email, and phone values.
- `Invoice History`, `Submitted payments`, and `Payment History` are rendered as tables with headers.
- The page remains readable in dark mode.
- No billing workflow or business-logic behavior changes.
