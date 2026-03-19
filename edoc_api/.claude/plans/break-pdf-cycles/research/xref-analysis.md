# Xref Dependency Analysis

## Summary

- **Total files:** 134 (nodes)
- **Runtime dependencies:** 436 (edges)
- **Circular dependency cycles:** 38

## PDF-Specific Cycles (4 cycles, 8-9 nodes each)

### 1. Contract PDF Cycle (9 nodes)
```
contract_pdf.ex
  → pdf_templates.ex
  → contract_html.ex
  → router.ex
  → public_document_controller.ex
  → document_delivery.ex
  → share_templates.ex
  → document_renderer.ex
  → contract_pdf.ex
```

### 2. Act PDF Cycle (9 nodes)
```
act_pdf.ex
  → pdf_templates.ex
  → contract_html.ex
  → router.ex
  → public_document_controller.ex
  → document_delivery.ex
  → share_templates.ex
  → document_renderer.ex
  → act_pdf.ex
```

### 3. Invoice PDF Cycle - Email (9 nodes)
```
email_builder.ex
  → document_renderer.ex
  → invoice_pdf.ex
  → pdf_templates.ex
  → contract_html.ex
  → router.ex
  → public_document_controller.ex
  → document_delivery.ex
  → email_builder.ex
```

### 4. Invoice PDF Cycle - UI (8 nodes)
```
document_delivery_ui.ex
  → document_renderer.ex
  → invoice_pdf.ex
  → pdf_templates.ex
  → contract_html.ex
  → router.ex
  → document_delivery_html_controller.ex
  → document_delivery_ui.ex
```

## Root Cause Analysis

### Key Architectural Violations

1. **Web Layer Pollution**: `pdf_templates.ex` imports `Repo` and business logic modules
2. **Cross-Context Dependencies**: Contract HTML controller used by all PDF templates
3. **Shared Router Dependency**: Every cycle includes `router.ex`
4. **Tight Coupling**: Document renderer directly imports all PDF modules
5. **Mixed Responsibilities**: `document_delivery.ex` orchestrates both UI and email flows

### Files Requiring Changes

**Core (edoc_api):**
- `lib/edoc_api/documents/contract_pdf.ex` — calls PdfTemplates
- `lib/edoc_api/documents/invoice_pdf.ex` — calls PdfTemplates
- `lib/edoc_api/documents/act_pdf.ex` — calls PdfTemplates
- `lib/edoc_api/document_delivery/document_renderer.ex` — routes to PDF modules
- `lib/edoc_api/document_delivery/email_builder.ex` — uses renderer

**Web (edoc_api_web):**
- `lib/edoc_api_web/pdf_templates.ex` — 1385 lines, Phoenix.Component
- `lib/edoc_api_web/controllers/contract_html_controller.ex`
- `lib/edoc_api_web/controllers/invoices_controller.ex`
- `lib/edoc_api_web/controllers/acts_controller.ex`
- `lib/edoc_api_web/controllers/public_document_controller.ex`

## Break Points

The cycle can be broken at **3 points**:

1. **At PdfTemplates** — Move HTML generation to core using `embed_templates`
2. **At Document PDF modules** — Use dependency injection (pass HTML in)
3. **At Controllers** — Render HTML in web layer, pass to PDF modules

## Normal Router Cycles (Ignore - Expected in Phoenix)

24 cycles are controller → router → controller (3 nodes each). These are expected Phoenix patterns and NOT problematic.
