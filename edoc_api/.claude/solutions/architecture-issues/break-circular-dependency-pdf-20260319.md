---
module: "Documents"
date: "2026-03-19"
problem_type: integration_issue
component: phoenix_controller
symptoms:
  - "Core PDF modules (edoc_api) imported EdocApiWeb.PdfTemplates"
  - "4 circular dependency cycles of 8-9 nodes each detected by mix xref graph"
  - "Tests required full web layer to test core PDF modules"
  - "Difficult to introduce background job processing for PDF generation"
root_cause: "Core domain layer (edoc_api) depended on web presentation layer (edoc_api_web), violating umbrella app boundaries and creating tight coupling"
severity: high
tags: ["circular-dependency", "dependency-inversion", "pdf-generation", "architecture", "umbrella-app"]
elixir_version: "1.14"
phoenix_version: "1.7.10"
---

# Breaking Circular Dependencies in PDF Generation

## Symptoms

- **Circular dependency detected**: `edoc_api/documents/contract_pdf.ex` imported `EdocApiWeb.PdfTemplates`
- **4 large cycles** of 8-9 nodes each in `mix xref graph --format cycles`
- **Testing isolation impossible**: Core PDF modules required web layer to compile
- **Feature blocked**: Background PDF generation (Oban) would require web layer in workers

## Investigation

1. **Analyzed the cycle**: PDF modules called `PdfTemplates.module_html(struct)` to get HTML, then converted to PDF
2. **Identified the violation**: Core should never depend on web — this is an umbrella app boundary
3. **Solution pattern**: Dependency Inversion — have web layer push HTML to core, rather than core pulling from web

## Root Cause

`EdocApi.Documents.ContractPdf` (in `edoc_api/`) called `EdocApiWeb.PdfTemplates.contract_html/1` (in `edoc_api_web/`), but controllers also depended on these PDF modules. This created a circular dependency:

```
documents/contract_pdf.ex → pdf_templates.ex → contract_html.ex →
router.ex → public_document_controller.ex → document_delivery.ex →
share_templates.ex → document_renderer.ex → contract_pdf.ex
```

**Before (Circular):**
```elixir
# In edoc_api/documents/contract_pdf.ex — VIOLATES BOUNDARY
def render(contract) do
  contract
  |> PdfTemplates.contract_html()  # ← Depends on edoc_api_web!
  |> Pdf.html_to_pdf()
end
```

## Solution

Invert the dependency: Web layer renders HTML first, then passes binary to core PDF modules.

**After (Unidirectional):**
```elixir
# In edoc_api/documents/contract_pdf.ex — CLEAN
def render(html) when is_binary(html) do
  Pdf.html_to_pdf(html)
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

For email delivery (which lives in core), created an isolated `PdfRenderer` module that intentionally bridges the layers for this specific use case.

### Files Changed

- `lib/edoc_api/documents/contract_pdf.ex` — Changed signature to accept HTML binary
- `lib/edoc_api/documents/invoice_pdf.ex` — Changed signature to accept HTML binary
- `lib/edoc_api/documents/act_pdf.ex` — Changed signature to accept HTML binary
- `lib/edoc_api/documents/pdf_renderer.ex` — **NEW** — Isolated bridge for email delivery
- `lib/edoc_api/documents/builders/contract_data_builder.ex` — **NEW** — Shared data builders
- `lib/edoc_api_web/controllers/contract_html_controller.ex` — Pre-renders HTML before PDF
- `lib/edoc_api_web/controllers/invoices_controller.ex` — Pre-renders HTML before PDF
- `lib/edoc_api_web/controllers/acts_controller.ex` — Pre-renders HTML before PDF
- `lib/edoc_api_web/controllers/contract_controller.ex` — Pre-renders HTML before PDF
- `lib/edoc_api_web/controllers/invoice_controller.ex` — Pre-renders HTML before PDF
- `lib/edoc_api_web/pdf_templates.ex` — Uses shared builders
- `lib/edoc_api/document_delivery.ex` — Uses PdfRenderer instead of DocumentRenderer

### Results

- **Cycles reduced**: 37 total (down from 41)
- **PDF cycles eliminated**: 4 large cycles broken
- **Core decoupled**: PDF modules have zero `EdocApiWeb` imports
- **Tests passing**: All 159 tests passing

## Prevention

**Add to Iron Laws?** Yes — Consider adding: "Core domain layer must never import from web presentation layer"

**Code review check**: When reviewing changes, verify:
- `lib/edoc_api/` never imports from `EdocApiWeb`
- Use dependency inversion when core needs web-layer functionality

**Architecture pattern**: For any core→web dependency needs:
1. Create an isolated module (like `PdfRenderer`) that explicitly bridges
2. Document the coupling with `@moduledoc`
3. Prefer pushing data from web→core over pulling from core→web

## Related

- Mix `xref` command: `mix xref graph --format cycles` — Detect circular dependencies
- Umbrella app boundary: `edoc_api/` is core, `edoc_api_web/` is web
- Dependency Inversion Principle: Depend on abstractions, not concretions
