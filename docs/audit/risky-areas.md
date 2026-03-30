# Risky Areas Audit

## Duplicated or drifting business rules
- Invoice issuing checks live in `EdocApi.Invoicing.mark_invoice_issued/1`, but controller still maps error cases manually. If status rules change, HTTP mapping can drift.
  - Files: `edoc_api/lib/edoc_api/invoicing.ex`, `edoc_api/lib/edoc_api_web/controllers/invoice_controller.ex`
  - Refactor: centralize status transitions and expose a typed error; add a single error-to-HTTP mapper.

## Missing or weak validations
- `Company` now requires `bank_id`, `kbe_code_id`, `knp_code_id`, but API doesn’t offer clear defaults or UX for missing fields.
  - Files: `edoc_api/lib/edoc_api/core/company.ex`, `edoc_api/lib/edoc_api_web/controllers/company_controller.ex`
  - Refactor: introduce changeset variants for create/update, or defaults from dictionaries.
- `InvoiceItem` parsing falls back to defaults on invalid input, which can silently accept bad data.
  - Files: `edoc_api/lib/edoc_api/invoicing.ex`, `edoc_api/lib/edoc_api/core/invoice_item.ex`
  - Refactor: convert parse failures into validation errors rather than defaulting.

## Inconsistent error handling
- Controllers return different error shapes/statuses and embed error mapping logic.
  - Files: `edoc_api/lib/edoc_api_web/controllers/*`
  - Refactor: add `EdocApiWeb.ErrorMapper` for consistent status + error format.
- PDF endpoint leaks internal errors in responses.
  - Files: `edoc_api/lib/edoc_api_web/controllers/invoice_controller.ex`
  - Refactor: log internal reason and return stable error code only.

## Likely to break with new requirements (multiple banks per company)
- Invoices currently pull bank details from `company` instead of a specific bank account, which will be wrong with multiple accounts.
  - Files: `edoc_api/lib/edoc_api/invoicing.ex`, `edoc_api/lib/edoc_api_web/pdf_templates.ex`
  - Refactor: store `invoice.bank_account_id` and snapshot fields; render PDF from invoice bank account or snapshot.
- `Company` has both `bank_name` and `bank_id`, which can drift.
  - Files: `edoc_api/lib/edoc_api/core/company.ex`, `edoc_api/lib/edoc_api/core/bank.ex`
  - Refactor: pick one source of truth (dictionary reference) or explicitly treat `bank_name` as snapshot.

## Suggested refactors (incremental)
1) Add `EdocApiWeb.ErrorMapper` and update controllers to standardize error responses.
2) Fill `invoice.bank_account_id` at creation and render PDF from invoice bank account/snapshots.
3) Treat invalid numeric input as validation errors (no silent fallback).
