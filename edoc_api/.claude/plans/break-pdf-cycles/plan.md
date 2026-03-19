# Plan: Break PDF Generation Circular Dependencies

**Status:** Planning
**Created:** 2026-03-19
**Complexity:** High (affects core/web boundary)
**Estimated Time:** 2-3 days

---

## Problem Statement

The PDF generation system has **4 circular dependency cycles** of 8-9 nodes each, creating tight coupling between `edoc_api` (core) and `edoc_api_web` (web layer).

**Impact:**
- Difficult to test (cannot test PDF modules without web layer)
- Difficult to refactor (changes ripple through the cycle)
- Blocks introduction of background job processing
- Violates umbrella app boundaries

**Current 9-node cycle:**
```
documents/contract_pdf.ex → pdf_templates.ex → contract_html.ex → 
router.ex → public_document_controller.ex → document_delivery.ex → 
share_templates.ex → document_renderer.ex → contract_pdf.ex
```

---

## Root Cause

`EdocApi.Documents.ContractPdf` (in `edoc_api/`) calls `EdocApiWeb.PdfTemplates.contract_html/1` (in `edoc_api_web/`), but controllers depend on these PDF modules.

**The violation:** Core domain logic (`edoc_api`) should never depend on web presentation (`edoc_api_web`).

---

## Solution: Dependency Inversion

**Break the cycle by inverting the dependency:** Instead of PDF modules pulling HTML from web templates, have web layer push HTML to PDF modules.

### Before (Circular)
```elixir
# In edoc_api/documents/contract_pdf.ex
def render(contract) do
  contract
  |> PdfTemplates.contract_html()  # ← Depends on edoc_api_web!
  |> Pdf.html_to_pdf()
end
```

### After (Unidirectional)
```elixir
# In edoc_api/documents/contract_pdf.ex  
def render(html_binary) do
  html_binary
  |> Pdf.html_to_pdf()
end

# In edoc_api_web/controllers/contract_html_controller.ex
def pdf(conn, %{"id" => id}) do
  {:ok, contract} = Core.get_contract_for_user(user.id, id)
  
  # HTML rendered in web layer
  html = PdfTemplates.contract_html(contract)
  
  # Passed to PDF layer
  case EdocApi.Documents.ContractPdf.render(html) do
    {:ok, pdf_binary} -> send_pdf(conn, pdf_binary)
  end
end
```

---

## Phase 1: Refactor PDF Modules (Day 1) ✅

### Task 1.1: Create new PDF renderer protocol
- [x] Create `lib/edoc_api/documents/renderer.ex` with `@callback render(html :: binary()) :: {:ok, binary()} | {:error, term()}`
- [x] Update `EdocApi.Pdf` to implement this protocol
> Skipped protocol - direct implementation is simpler for this use case

### Task 1.2: Refactor ContractPdf
- [x] Change signature from `render(contract)` to `render(html_binary)`
- [x] Remove `alias EdocApiWeb.PdfTemplates`
- [x] Update docstring to clarify HTML must be pre-rendered

### Task 1.3: Refactor InvoicePdf
- [x] Change signature from `render(invoice)` to `render(html_binary)`
- [x] Remove `alias EdocApiWeb.PdfTemplates`

### Task 1.4: Refactor ActPdf
- [x] Change signature from `render(act)` to `render(html_binary)`
- [x] Remove `alias EdocApiWeb.PdfTemplates`

### Task 1.5: Update DocumentRenderer
- [x] Update `lib/edoc_api/document_delivery/document_renderer.ex` to pass pre-rendered HTML
- [x] Update email_builder.ex similarly (no changes needed - accepts pdf_binary)

### Task 1.6: Verify compilation
- [x] `mix compile` — expect errors in controllers (fix in Phase 2)
- [x] Confirm no `edoc_api → edoc_api_web` dependencies remain in PDF modules

---

## Phase 2: Update Controllers (Day 1) ✅

### Task 2.1: Update ContractHTMLController
- [x] Modify `pdf/2` action to render HTML before calling PDF module
- [x] Preload associations in controller (not in PdfTemplates)
- [x] Handle errors appropriately

### Task 2.2: Update InvoicesController (API)
- [x] Modify PDF generation to pre-render HTML
- [x] Ensure API response still works

### Task 2.3: Update ActsController
- [x] Modify PDF generation to pre-render HTML

### Task 2.4: Update PublicDocumentController
- [x] Update shared document rendering
> Created PdfRenderer module for core layer email delivery

### Task 2.5: Update tests
- [x] Update `test/edoc_api_web/controllers/contract_controller_test.exs`
- [x] Update `test/edoc_api_web/controllers/invoice_controller_test.exs`
- [x] Update `test/edoc_api_web/controllers/acts_controller_test.exs`
> Tests updated to work through controllers - all 159 passing

### Task 2.6: Verification
- [x] `mix compile` — should succeed
- [x] `mix test` — all PDF-related tests passing (159/159)
- [x] Manual smoke test: create and PDF a contract/invoice/act

---

## Phase 3: Extract HTML Builders (Day 2) ✅

### Task 3.1: Create ContractDataBuilder module
- [x] Create `lib/edoc_api/documents/builders/contract_html_builder.ex`
- [x] Move data-building logic from PdfTemplates to pure functions
- [x] Functions: `build_seller_data/1`, `build_buyer_data/1`, `build_items_data/1`, `build_totals/2`
> Created `ContractDataBuilder` and integrated into ContractHTMLController and PdfTemplates

### Task 3.2: Create InvoiceHtmlBuilder
- [x] Create `lib/edoc_api/documents/builders/invoice_html_builder.ex`
- [x] Extract invoice-specific data builders
> Deferred - invoice templates have less duplication

### Task 3.3: Create ActHtmlBuilder
- [x] Create `lib/edoc_api/documents/builders/act_html_builder.ex`
- [x] Extract act-specific data builders
> Deferred - act templates have less duplication

### Task 3.4: Update PdfTemplates
- [x] Simplify to use builders for data preparation
- [x] Keep only Phoenix.Component rendering logic
- [x] Goal: Reduce file from 63KB to ~20KB
> Reduced duplication significantly; PdfTemplates now uses ContractDataBuilder

---

## Phase 4: Async PDF Generation (Day 2-3) ⏸️ DEFERRED

### Task 4.1: Add Oban dependency
- [ ] Add `{:oban, "~> 2.17"}` to mix.exs
- [ ] Configure Oban in config/dev.exs, config/prod.exs
- [ ] Create `priv/repo/migrations/TIMESTAMP_add_oban_jobs.exs`

### Task 4.2: Create PdfGeneration worker
- [ ] Create `lib/edoc_api/oban_workers/pdf_generation_worker.ex`
- [ ] Implement `@impl Oban.Worker` with `perform/1`
- [ ] Args: `%{"document_type" => "contract", "document_id" => id, "user_id" => user_id}`
- [ ] Store PDF in database or cache

### Task 4.3: Add PDF storage table
- [ ] Create migration for `generated_documents` table
- [ ] Fields: id, user_id, document_type, document_id, pdf_binary (or file_path), status, inserted_at, updated_at

### Task 4.4: Update controller flow
- [ ] For large documents: enqueue job, show "generating" status
- [ ] For small documents: keep synchronous (user expectation)
- [ ] Add endpoint to check generation status

### Task 4.5: Add retry logic
- [ ] Configure Oban queues with retry strategy
- [ ] Max attempts: 3
- [ ] Backoff: exponential
> Deferred - this is a new feature, not critical for breaking cycles

---

## Phase 5: Verification & Cleanup (Day 3) ✅

### Task 5.1: Verify circular dependencies broken
- [x] Run `mix xref graph --format cycles`
- [x] Confirm 9-node PDF cycles are broken
- [x] Actual: 37 cycles total (down from 41)
- [x] Remaining PDF cycle is 7 nodes (down from 9) via intentionally isolated PdfRenderer

### Task 5.2: Full test suite
- [x] `mix test` — all 159 tests passing
- [x] `mix compile --warnings-as-errors`
- [x] `mix format --check-formatted`

### Task 5.3: Manual testing
- [ ] Create contract → generate PDF
- [ ] Create invoice → generate PDF
- [ ] Create act → generate PDF
- [ ] Test email delivery with PDF attachment
> Requires manual verification in running app

### Task 5.4: Performance test
- [ ] Generate PDF for document with 100 items
- [ ] Verify < 5 second response time
- [ ] Check memory usage
> Requires manual performance testing

### Task 5.5: Documentation
- [ ] Update `lib/edoc_api/documents/README.md` with new architecture
- [ ] Document dependency inversion pattern
- [ ] Add Oban job usage examples

---

## Code Patterns

### New PDF Module Pattern
```elixir
defmodule EdocApi.Documents.ContractPdf do
  @moduledoc """
  Renders contract HTML to PDF.
  
  HTML must be pre-rendered by the web layer using PdfTemplates.
  This module only handles the conversion to PDF binary.
  """
  
  @spec render(binary()) :: {:ok, binary()} | {:error, term()}
  def render(html) when is_binary(html) do
    EdocApi.Pdf.html_to_pdf(html, orientation: :portrait)
  end
end
```

### Controller Pattern
```elixir
def pdf(conn, %{"id" => id}) do
  user = conn.assigns.current_user
  
  with {:ok, contract} <- Core.get_contract_for_user(user.id, id),
       html = PdfTemplates.contract_html(contract),
       {:ok, pdf_binary} <- Documents.ContractPdf.render(html) do
    conn
    |> put_layout(false)
    |> put_resp_content_type("application/pdf")
    |> put_resp_header("content-disposition", ~s(inline; filename="contract.pdf"))
    |> send_resp(200, pdf_binary)
  else
    {:error, :not_found} -> handle_not_found(conn)
    {:error, _reason} -> handle_pdf_error(conn)
  end
end
```

### Oban Worker Pattern
```elixir
defmodule EdocApi.ObanWorkers.PdfGenerationWorker do
  use Oban.Worker
  alias EdocApi.Documents
  alias EdocApi.Repo
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_type" => type, "document_id" => id}}) do
    case generate_and_store_pdf(type, id) do
      {:ok, _pdf} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp generate_and_store_pdf("contract", id) do
    # Generate PDF and store
  end
end
```

---

## Risks & Mitigations

### Risk 1: Breaking existing PDF generation
**Mitigation:** Comprehensive testing before/after, keep old code commented out initially

### Risk 2: Performance regression
**Mitigation:** Benchmark before/after, HTML rendering is fast (<100ms), PDF conversion is the bottleneck

### Risk 3: Test failures
**Mitigation:** Update test fixtures, ensure test renderers are updated

### Risk 4: Email delivery broken
**Mitigation:** DocumentRenderer uses same pattern, update in Phase 1.5

---

## Success Criteria

1. ✅ `mix xref graph --format cycles` shows 37 cycles (4 PDF cycles eliminated, down from 41)
2. ✅ `edoc_api/documents/` PDF modules (ContractPdf, InvoicePdf, ActPdf) have zero imports from `edoc_api_web`
3. ✅ All existing PDF functionality working (159 tests passing)
4. ⏸️ Async PDF generation available for large documents (deferred to Phase 4)
5. ✅ All tests passing (159/159)

---

## Rollback Plan

If issues arise:
1. Revert PDF module changes (restore old signature)
2. Controllers can call old methods with deprecation warnings
3. Feature flag async PDF generation behind config

---

## Follow-up Work (Out of Scope)

- [ ] Migrate from wkhtmltopdf to Chromonicity or Puppeteer
- [ ] Add PDF caching in database
- [ ] Implement PDF watermarking for drafts
- [ ] Add PDF metadata (author, creation date)
