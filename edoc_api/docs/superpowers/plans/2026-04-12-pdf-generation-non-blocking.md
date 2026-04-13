# Non-Blocking PDF Generation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove synchronous `wkhtmltopdf` work from HTTP request handlers for invoice/contract/act PDF routes.

**Architecture:** Move HTML and API PDF endpoints to a cache-first workflow backed by `generated_documents` and `PdfGenerationWorker`. If PDF is cached, return immediately; if not cached, enqueue generation and return a non-blocking response (HTML: redirect with flash, API: `202 Accepted` with poll hint). Add status/read endpoints for API polling and update tests.

**Tech Stack:** Phoenix 1.7, Ecto, Oban, existing `EdocApi.ObanWorkers.PdfGenerationWorker`, ExUnit.

---

## File map

- Modify: `lib/edoc_api_web/controllers/invoices_controller.ex`
- Modify: `lib/edoc_api_web/controllers/acts_controller.ex`
- Modify: `lib/edoc_api_web/controllers/contract_html_controller.ex`
- Modify: `lib/edoc_api_web/controllers/invoice_controller.ex` (API `/v1`)
- Modify: `lib/edoc_api_web/controllers/contract_controller.ex` (API `/v1`)
- Modify: `lib/edoc_api_web/router.ex` (API PDF status route(s))
- Create: `lib/edoc_api/documents/pdf_requests.ex` (shared cache/enqueue orchestration)
- Modify: `lib/edoc_api/oban_workers/pdf_generation_worker.ex` (idempotent enqueue helper)
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
- Modify: `test/edoc_api_web/controllers/invoices_controller_test.exs`
- Modify: `test/edoc_api_web/controllers/acts_controller_test.exs`
- Modify: `test/edoc_api_web/controllers/contract_html_controller_test.exs`
- Modify: `test/edoc_api_web/controllers/invoice_controller_test.exs`
- Modify: `test/edoc_api_web/controllers/contract_controller_test.exs`
- Create: `test/edoc_api/documents/pdf_requests_test.exs`

---

## Chunk 1: Core orchestration (cache-first + enqueue)

### Task 1: Add failing tests for cache/enqueue behavior

**Files:**
- Create: `test/edoc_api/documents/pdf_requests_test.exs`
- Test: `lib/edoc_api/documents/pdf_requests.ex`

- [ ] **Step 1: Write failing tests**
  - cached PDF returns `{:ok, pdf_binary}` without enqueue
  - cache miss enqueues and returns `{:pending, :enqueued}`
  - repeated cache miss while pending does not duplicate enqueue

- [ ] **Step 2: Run test to verify it fails**
  - Run: `mix test test/edoc_api/documents/pdf_requests_test.exs`
  - Expected: FAIL (module/function missing)

- [ ] **Step 3: Implement minimal orchestration module**
  - Add `EdocApi.Documents.PdfRequests` with:
    - `fetch_or_enqueue(type, document_id, user_id, html_binary)`
    - `status(type, document_id, user_id)`
  - Reuse `PdfGenerationWorker.get_pdf/3` and enqueue helper.

- [ ] **Step 4: Verify tests pass**
  - Run: `mix test test/edoc_api/documents/pdf_requests_test.exs`
  - Expected: PASS

- [ ] **Step 5: Commit**
  - `git commit -m "feat(pdf): add cache-first enqueue orchestration"`

---

## Chunk 2: HTML controllers become non-blocking

### Task 2: Convert `/invoices/:id/pdf`, `/acts/:id/pdf`, `/contracts/:id/pdf`

**Files:**
- Modify: `lib/edoc_api_web/controllers/invoices_controller.ex`
- Modify: `lib/edoc_api_web/controllers/acts_controller.ex`
- Modify: `lib/edoc_api_web/controllers/contract_html_controller.ex`
- Modify: `priv/gettext/ru/LC_MESSAGES/default.po`
- Modify: `priv/gettext/kk/LC_MESSAGES/default.po`
- Test: `test/edoc_api_web/controllers/invoices_controller_test.exs`
- Test: `test/edoc_api_web/controllers/acts_controller_test.exs`
- Test: `test/edoc_api_web/controllers/contract_html_controller_test.exs`

- [ ] **Step 1: Write failing controller tests**
  - cache hit path: returns `200` PDF immediately
  - cache miss path: redirects back to show page with localized “PDF is being prepared”
  - second request after worker completion returns `200` PDF

- [ ] **Step 2: Run targeted tests (expect fail)**
  - `mix test test/edoc_api_web/controllers/invoices_controller_test.exs`
  - `mix test test/edoc_api_web/controllers/acts_controller_test.exs`
  - `mix test test/edoc_api_web/controllers/contract_html_controller_test.exs`

- [ ] **Step 3: Implement controller changes**
  - Replace direct `*Pdf.render(html)` in request with `PdfRequests.fetch_or_enqueue(...)`
  - On `{:ok, pdf}`: send response as before.
  - On `{:pending, _}`: flash + redirect.
  - On generation failure status: flash localized error.

- [ ] **Step 4: Run tests**
  - Run three targeted suites again; expected PASS.

- [ ] **Step 5: Commit**
  - `git commit -m "feat(pdf): make HTML pdf endpoints non-blocking"`

---

## Chunk 3: API parity (`/v1/.../pdf`) + polling endpoint

### Task 3: Non-blocking API response contract

**Files:**
- Modify: `lib/edoc_api_web/controllers/invoice_controller.ex`
- Modify: `lib/edoc_api_web/controllers/contract_controller.ex`
- Modify: `lib/edoc_api_web/router.ex`
- Test: `test/edoc_api_web/controllers/invoice_controller_test.exs`
- Test: `test/edoc_api_web/controllers/contract_controller_test.exs`

- [ ] **Step 1: Write failing API tests**
  - cache miss on `GET /v1/.../:id/pdf` returns `202` JSON:
    - `status: "pending"`
    - `poll_url`
  - cache hit returns `200` PDF.
  - status endpoint returns `pending|ready|failed`.

- [ ] **Step 2: Run targeted API tests (expect fail)**
  - `mix test test/edoc_api_web/controllers/invoice_controller_test.exs`
  - `mix test test/edoc_api_web/controllers/contract_controller_test.exs`

- [ ] **Step 3: Implement API behavior**
  - Keep existing `200` PDF response for cache hit.
  - Return `202` for enqueued generation.
  - Add status route(s), e.g. `/v1/invoices/:id/pdf/status`, `/v1/contracts/:id/pdf/status`.

- [ ] **Step 4: Run tests**
  - Run the same targeted API tests; expected PASS.

- [ ] **Step 5: Commit**
  - `git commit -m "feat(pdf): add non-blocking API pdf workflow with status polling"`

---

## Chunk 4: Worker idempotency + final verification

### Task 4: Prevent duplicate jobs and validate full suite

**Files:**
- Modify: `lib/edoc_api/oban_workers/pdf_generation_worker.ex`
- Test: `test/edoc_api/documents/pdf_requests_test.exs`

- [ ] **Step 1: Write failing test for duplicate enqueue prevention**
  - Two rapid `fetch_or_enqueue` calls for same `(type, doc_id, user_id)` should produce one active job.

- [ ] **Step 2: Implement idempotent enqueue**
  - Add unique-key strategy at application level:
    - check existing `generated_documents` status (`pending|processing`) before enqueue, and/or
    - use deterministic uniqueness in Oban job args.

- [ ] **Step 3: Verify tests**
  - `mix test test/edoc_api/documents/pdf_requests_test.exs`

- [ ] **Step 4: Run integration and full suite**
  - `mix test test/edoc_api_web/controllers/invoices_controller_test.exs`
  - `mix test test/edoc_api_web/controllers/acts_controller_test.exs`
  - `mix test test/edoc_api_web/controllers/contract_html_controller_test.exs`
  - `mix test test/edoc_api_web/controllers/invoice_controller_test.exs`
  - `mix test test/edoc_api_web/controllers/contract_controller_test.exs`
  - `mix test`

- [ ] **Step 5: Commit**
  - `git commit -m "refactor(pdf): enforce idempotent async generation and verify full suite"`

---

## Rollout notes

- Keep current public document `/public/docs/:token/pdf` path unchanged in this slice (separate optimization).
- Feature flag recommended for first rollout:
  - `config :edoc_api, :non_blocking_pdf, true`
  - fallback to synchronous render if disabled.
- Operational metric to add after merge:
  - `pdf.request.pending.count`
  - `pdf.request.cache_hit.count`
  - `pdf.generation.duration_ms`

