**Contract PDF Issuance Plan (Mirror Invoice Workflow)**
- **Goal & Success Criteria**: Add contract issuance + PDF generation that mirrors invoices; `POST /v1/contracts/:id/issue` sets `status=issued` + `issued_at`, `GET /v1/contracts/:id/pdf` returns a PDF; controller responses include new fields; tests cover issue + pdf; `mix test` passes.
- **Non-goals / Out of Scope**: Full contract editing UI, signatures, PDF persistence/storage, auto-numbering (kept manual), changing invoice behavior.
- **Assumptions**: Existing contracts are treated as already issued on migration (backfill `status=issued`, `issued_at=COALESCE(date, inserted_at)`); `body_html` is stored and sanitized on write; PDF generation stays on-demand using wkhtmltopdf (no caching).
- **Proposed Solution**: Add `status`, `issued_at`, and `body_html` to contracts; implement `ContractStatus` helpers; add contract issue logic in Core (or a small contract context) with idempotency checks; create `ContractPdf` + `PdfTemplates.contract_html/1`; add contract `pdf` and `issue` endpoints in controller + router; extend JSON view for new fields; add tests.
- **Alternatives Considered**:
  - No state change on issue → simpler, but not truly “issuance” and diverges from invoice workflow.
  - Store PDF blobs in DB/object storage → persistent, but higher complexity and ops; not required to mirror invoices.
  - Keep template static without `body_html` → safer but ignores requirement to store rich text/HTML.

**System Design**
- **Data Model**: `contracts` add `status` (string), `issued_at` (utc_datetime), `body_html` (text). `status` defaults to draft for new contracts, existing backfilled to issued.
- **Issuance Flow**: `ContractController.issue` → `Core.issue_contract_for_user(user_id, id)` → load contract (company-scoped), ensure not already issued, update `status` + `issued_at`, return updated contract.
- **PDF Flow**: `ContractController.pdf` → load contract + company → render HTML with `PdfTemplates.contract_html/1` → `Pdf.html_to_pdf/1` → send PDF response.
- **Error Handling**: Add `:contract_not_found`, `:contract_already_issued`, `:cannot_issue` mappings in `ControllerHelpers` or controller-local error_map.

**Interfaces & Data Contracts**
- **POST /v1/contracts/:id/issue** → 200 `{data: contract}`; 404 `contract_not_found`; 422 `contract_already_issued`.
- **GET /v1/contracts/:id/pdf** → `application/pdf`, `content-disposition: inline; filename="contract-<number>.pdf"`.
- **Contract JSON** (`lib/edoc_api_web/views/contract_json.ex`): add `status`, `issued_at`, `body_html`.

**Execution Details**
- Add migration `priv/repo/migrations/*_add_contract_issuance_fields.exs` to add `status`, `issued_at`, `body_html`, plus backfill existing rows.
- Update schema + changeset in `lib/edoc_api/core/contract.ex`:
  - Add fields `status`, `issued_at`, `body_html`.
  - Set default status (`ContractStatus.default/0`), validate inclusion, sanitize `body_html` (e.g., `HtmlSanitizeEx` whitelist).
- Add `lib/edoc_api/contract_status.ex` (similar to `invoice_status.ex`) with `default/0`, `issued/0`, `draft/0`, `can_issue?/1`, `already_issued?/1`.
- Extend `lib/edoc_api/core.ex` with `issue_contract_for_user/2` and update `get_contract_for_user/2` to preload `:company` (for PDF) or add a preload in controller.
- Add `lib/edoc_api/documents/contract_pdf.ex` mirroring `invoice_pdf.ex`.
- Extend `lib/edoc_api_web/pdf_templates.ex` with `contract_html/1` + HEEx template; render sanitized `body_html` via `Phoenix.HTML.raw/1`; include company details and contract number/date/title.
- Update `lib/edoc_api_web/controllers/contract_controller.ex` to add `issue/2` and `pdf/2`, use `ControllerHelpers.handle_common_result/4` with contract-specific error mapping.
- Update `lib/edoc_api_web/router.ex` with `post "/contracts/:id/issue"` and `get "/contracts/:id/pdf"`.
- Add dependency for HTML sanitization in `mix.exs` (e.g., `:html_sanitize_ex`) and implement sanitization in contract changeset.
- Add/extend tests:
  - `test/edoc_api_web/controllers/contract_controller_test.exs` for issue and pdf endpoints.
  - `test/edoc_api/core/contract_issue_test.exs` for issuance rules.
  - Extend `test/edoc_api/pdf_test.exs` for contract PDF generation.
  - Update fixtures in `test/support/fixtures.ex` to include `body_html` and status defaults.

**Testing & Quality**
- Unit tests: `ContractStatus` helpers; changeset validation/sanitization.
- Controller tests: 200/404/422 for issue; pdf response content-type and filename.
- PDF test: guard with `System.find_executable("wkhtmltopdf")` like invoice PDF test.

**Rollout, Observability, and Ops**
- Run migration + backfill in staging first; verify existing contracts are `issued`.
- Ensure wkhtmltopdf installed in runtime environment.
- Log PDF generation errors (`pdf_generation_failed`) and surface 422 with details.

**Risks & Mitigations**
- **HTML injection / external resource loading**: sanitize `body_html` with a strict whitelist; avoid remote assets.
- **Backfill misclassification**: document assumption; if uncertain, add a one-off script to set status per business rules.
- **wkhtmltopdf failures**: keep existing error handling + test in staging.

**Open Questions**
- None; proceed with the assumptions above.

**Implementation Summary (2026-01-27)**
- Added contract issuance state and HTML storage with sanitization/validation so contracts can be issued and rendered safely.
- Implemented contract issue + PDF flows mirroring invoices (controller actions, PDF renderer, template).
- Added migration to backfill existing contracts as issued and set `issued_at` from `date` or `inserted_at`.
- Extended contract JSON responses to include `status`, `issued_at`, `body_html`.
- Added tests for status helpers, changeset sanitization, issue logic, controller endpoints, and PDF generation.
