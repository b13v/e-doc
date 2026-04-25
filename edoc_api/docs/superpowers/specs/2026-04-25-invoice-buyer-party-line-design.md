# Invoice Buyer Party Line Design

## Goal

Fix the buyer row on `/invoices/:id` so it contains the same legal-party completeness as the seller row and keep the downloaded invoice PDF identical to the page preview.

Today the buyer row only shows:

- BIN/IIN
- buyer name
- address

It must also include:

- buyer legal form
- `Республика Казахстан`
- city before the address

Example target shape:

`БИН/ИИН <bin>, <legal form> <name>, Республика Казахстан, г. <city>, <address>`

## Scope

This change applies to:

- invoice HTML preview on `/invoices/:id`
- invoice PDF rendering on `/invoices/:id/pdf`
- invoice create/update flows for direct invoices without contract

This change does not alter seller rendering or contract/act rendering.

## Current State

The invoice show template and invoice PDF template each build the buyer row independently.

Current invoice preview buyer row:

- file: `lib/edoc_api_web/controllers/invoice_html/show.html.heex`
- currently renders BIN/IIN, optional legal form, optional city fragment, and address inline
- buyer legal form and city are resolved mainly from the linked contract buyer

Current invoice PDF buyer row:

- file: `lib/edoc_api_web/pdf_templates.ex`
- uses very similar but separate formatting logic

Problem areas:

1. HTML preview and PDF have duplicated buyer-row composition logic.
2. Direct invoices do not snapshot buyer city or buyer legal form onto the invoice.
3. Issued documents can therefore miss buyer city/legal form when no contract is linked.

## Requirements

### Functional

1. `/invoices/:id` must show a complete buyer party row.
2. `/invoices/:id/pdf` must show the same buyer party row as the HTML preview.
3. New and updated direct invoices must persist buyer city and buyer legal form on the invoice record.
4. Contract invoices must continue to work from linked contract/buyer data.
5. Historical invoices without the new snapshot fields must still render using best-effort fallback data.

### Rendering Rules

Buyer line format:

`БИН/ИИН <bin>, <legal form> <name>, Республика Казахстан, г. <city>, <address>`

Rules:

- `legal form` is included only when present
- `Республика Казахстан` is always included
- `г. <city>` is included only when city is present
- `address` is included only when present
- formatting must not leave doubled commas or dangling commas when optional fragments are absent

## Data Design

Add two fields to invoices:

- `buyer_city`
- `buyer_legal_form`

These fields act as buyer snapshot data for invoice rendering, primarily for direct invoices.

### Population Rules

For direct invoices without contract:

- when buyer is selected during create, copy buyer `city` and `legal_form` into the invoice
- when draft invoice buyer changes during update, refresh `buyer_city` and `buyer_legal_form`

For invoices from contract:

- no new contract-level persistence is required in this change
- renderers can still prefer linked contract buyer data where available

### Rendering Priority

For buyer legal form and city, renderers should resolve in this order:

1. explicit invoice snapshot fields: `buyer_legal_form`, `buyer_city`
2. linked contract buyer association
3. contract fallback fields if already stored on the contract
4. omit the fragment if unavailable

This keeps new direct invoices stable over time while preserving backward compatibility for historical invoices.

## Architecture

### Shared Formatter

Introduce one shared invoice buyer-party formatter/helper used by both:

- `lib/edoc_api_web/controllers/invoice_html/show.html.heex`
- `lib/edoc_api_web/pdf_templates.ex`

The formatter is responsible for:

- extracting buyer display parts from invoice/contract/buyer data
- normalizing missing fragments
- composing the final string without punctuation bugs

The formatter should return either:

- one fully formatted string for the buyer line

or:

- a small structured map of resolved buyer fragments plus a render helper

Recommendation: return structured fragments plus a small formatter function close to invoice rendering, so the resolution logic remains testable and the final text shape remains explicit.

### Invoice Persistence

Update invoice schema, migration, and invoice create/update paths so direct invoices snapshot:

- `buyer_city`
- `buyer_legal_form`

The write path should follow the same buyer lookup already used to fill buyer name, BIN/IIN, and address.

## Files Expected To Change

- `priv/repo/migrations/..._add_buyer_city_and_buyer_legal_form_to_invoices.exs`
- `lib/edoc_api/core/invoice.ex`
- `lib/edoc_api/invoicing.ex`
- `lib/edoc_api_web/controllers/invoice_html/show.html.heex`
- `lib/edoc_api_web/pdf_templates.ex`
- tests covering invoice rendering and invoice create/update behavior

## Error Handling

This feature is mostly additive and display-oriented.

Expected behavior:

- missing city does not fail rendering; it simply omits the city fragment
- missing legal form does not fail rendering; it simply omits the legal-form fragment
- create/update continues to succeed if buyer city is blank
- create/update continues to succeed if buyer legal form is blank or unavailable, though current buyer validation already normally provides it

No new user-facing error states are required.

## Compatibility

### Existing Invoices

Historical direct invoices may not have `buyer_city` or `buyer_legal_form`.

For those invoices:

- use fallback resolution from linked contract/buyer data when available
- otherwise render a reduced but correctly punctuated line

No backfill is required for correctness.

### Issued Documents

For newly created direct invoices, snapshotting city/legal form prevents later buyer-record edits from silently changing issued invoice party wording.

## Testing

Follow test-driven development.

### Required Tests

1. Invoice HTML show test reproducing the current missing buyer-party details and asserting the corrected buyer row.
2. Invoice PDF rendering test asserting the same buyer row content as the HTML preview.
3. Invoice create test for direct invoices proving `buyer_city` and `buyer_legal_form` are stored.
4. Invoice update test for direct draft invoices proving the snapshot fields refresh when buyer changes.
5. Regression test for missing optional fragments proving no malformed punctuation appears.

### Verification Standard

The change is complete only when:

- the failing buyer-row test passes
- the PDF test passes
- the full relevant test suite passes

## Non-Goals

- changing seller-row formatting
- changing contract buyer rendering
- backfilling all historical invoices
- adding country/city snapshot fields to other document types in this change
