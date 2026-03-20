# Documents — PDF Generation

This directory handles PDF generation for contracts, invoices, and acts.

## Architecture

### Dependency Inversion Pattern

**Key Principle:** Core domain logic (`edoc_api`) must never depend on web presentation (`edoc_api_web`). This prevents circular dependencies and maintains proper umbrella app boundaries.

**Before (Circular - Fixed):**
```elixir
# Core depending on Web = VIOLATION
defmodule EdocApi.Documents.ContractPdf do
  def render(contract) do
    contract
    |> EdocApiWeb.PdfTemplates.contract_html()  # ❌ Imports from web layer
    |> Pdf.html_to_pdf()
  end
end
```

**After (Unidirectional):**
```elixir
# Core only handles PDF conversion
defmodule EdocApi.Documents.ContractPdf do
  @spec render(binary()) :: {:ok, binary()} | {:error, term()}
  def render(html) when is_binary(html) do
    Pdf.html_to_pdf(html)  # ✅ Pure function, no web dependency
  end
end

# Web layer orchestrates the flow
defmodule EdocApiWeb.ContractHTMLController do
  def pdf(conn, %{"id" => id}) do
    contract = Core.get_contract_for_user(user.id, id)
    html = PdfTemplates.contract_html(contract)  # HTML rendered in web layer
    {:ok, pdf} = Documents.ContractPdf.render(html)  # Passed to core
    send_pdf(conn, pdf)
  end
end
```

### Module Structure

| Module | Purpose | Layer |
|--------|---------|-------|
| `ContractPdf` | Convert HTML → PDF for contracts | Core |
| `InvoicePdf` | Convert HTML → PDF for invoices | Core |
| `ActPdf` | Convert HTML → PDF for acts | Core |
| `PdfRenderer` | Bridge for core contexts (email delivery) | Core (isolated coupling) |
| `GeneratedDocument` | Schema for async PDF storage | Core |

### PdfRenderer: The Intentional Exception

`PdfRenderer` exists to support email delivery from the core `DocumentDelivery` context. It intentionally imports from `EdocApiWeb.PdfTemplates` because:

1. Email is triggered from core business logic, not web controllers
2. The coupling is isolated to a single module with clear documentation
3. Web controllers use PdfTemplates directly to avoid this bridge

**Usage Pattern:**
```elixir
# In core contexts (email delivery, background jobs)
PdfRenderer.render(:contract, contract)
# vs
# In web controllers
html = PdfTemplates.contract_html(contract)
ContractPdf.render(html)
```

## Synchronous PDF Generation

For most use cases, generate PDFs synchronously in the controller:

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
    {:error, :not_found} -> send_404(conn)
    {:error, _reason} -> send_500(conn)
  end
end
```

## Async PDF Generation with Oban

For large documents or batch operations, use the `PdfGenerationWorker`:

### Enqueue a PDF Generation Job

```elixir
def pdf_async(conn, %{"id" => id}) do
  user = conn.assigns.current_user

  with {:ok, contract} <- Core.get_contract_for_user(user.id, id),
       # Pre-render HTML before enqueueing (dependency inversion)
       html = PdfTemplates.contract_html(contract),
       {:ok, _job} <- PdfGenerationWorker.enqueue("contract", id, user.id, html) do
    json(conn, %{status: "generating", "message" => "PDF will be available shortly"})
  end
end
```

### Check PDF Status

```elixir
def pdf_status(conn, %{"id" => id}) do
  user = conn.assigns.current_user

  case PdfGenerationWorker.ready?("contract", id) do
    {:ok, _doc} -> json(conn, %{status: "ready"})
    {:error, :not_found} ->
      case PdfGenerationWorker.get_job_state(id) do
        "pending" -> json(conn, %{status: "generating"})
        "failed" -> json(conn, %{status: "failed", "error" => "Generation failed"})
        _ -> json(conn, %{status: "not_found"})
      end
  end
end
```

### Download Generated PDF

```elixir
def pdf_download(conn, %{"id" => id}) do
  user = conn.assigns.current_user

  case PdfGenerationWorker.get_pdf("contract", id, user.id) do
    {:ok, pdf_binary} ->
      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s(attachment; filename="contract.pdf"))
      |> send_resp(200, pdf_binary)

    {:error, :not_found} ->
      send_404(conn)
  end
end
```

## Worker Configuration

The `PdfGenerationWorker` is configured in `config/dev.exs` and `config/prod.exs`:

```elixir
config :edoc_api, Oban,
  repo: EdocApi.Repo,
  queues: [default: 10, pdf_generation: 5],
  plugins: [
    Oban.Plugins.Pruner,
    Oban.Plugins.Lifeline
  ]
```

**Queue Configuration:**
- `pdf_generation` queue: 5 concurrent jobs
- Max attempts: 3 (with exponential backoff)
- Timeout: 30 seconds per job

## Error Handling

### Worker Errors

The worker logs errors and marks failed documents in `generated_documents`:

```elixir
# Failed jobs are tracked with error messages
%GeneratedDocument{
  status: "failed",
  error_message: "wkhtmltopdf timeout"
}
```

### Controller Error Handling

```elixir
with {:ok, contract} <- Core.get_contract_for_user(user.id, id),
     html = PdfTemplates.contract_html(contract),
     {:ok, pdf_binary} <- Documents.ContractPdf.render(html) do
  # success
else
  {:error, :not_found} ->
    # Document doesn't exist or user doesn't have access
    conn
    |> put_status(404)
    |> json(%{error: "Document not found"})

  {:error, reason} ->
    # PDF generation failed (wkhtmltopdf error, timeout, etc.)
    Logger.error("PDF generation failed: #{inspect(reason)}")
    conn
    |> put_status(500)
    |> json(%{error: "Failed to generate PDF"})
end
```

## Testing

### Unit Tests

```elixir
defmodule EdocApi.Documents.ContractPdfTest do
  test "renders HTML to PDF" do
    html = "<html><body><h1>Test</h1></body></html>"

    assert {:ok, pdf_binary} = ContractPdf.render(html)
    assert is_binary(pdf_binary)
    assert byte_size(pdf_binary) > 0
  end

  test "returns error for invalid HTML" do
    assert {:error, _reason} = ContractPdf.render("not html")
  end
end
```

### Integration Tests (through controllers)

```elixir
defmodule ContractControllerTest do
  test "GET /contracts/:id/pdf returns PDF", %{conn: conn} do
    contract = insert(:contract)

    response =
      conn
      |> auth_user(contract.user)
      |> get(~p"/contracts/#{contract.id}/pdf")

    assert response.status == 200
    assert response.resp_content_type == "application/pdf"
    assert response.resp_body |> byte_size() > 0
  end
end
```

## Migration from wkhtmltopdf

The current implementation uses `wkhtmltopdf` via `EdocApi.Pdf.html_to_pdf/2`.

**Future improvements:**
- Migrate to Chromonicity or Puppeteer for better CSS support
- Add PDF caching in database (via `GeneratedDocument` schema)
- Implement PDF watermarking for drafts
- Add PDF metadata (author, creation date)

## Circular Dependency Resolution

This refactoring eliminated 4 circular dependency cycles (41 → 37 cycles total):

**Before:** 9-node cycle
```
documents/contract_pdf.ex → pdf_templates.ex → contract_html.ex →
router.ex → public_document_controller.ex → document_delivery.ex →
share_templates.ex → document_renderer.ex → contract_pdf.ex
```

**After:** 7-node cycle (via intentionally isolated PdfRenderer)
```
document_delivery.ex → pdf_renderer.ex → pdf_templates.ex →
contract_html.ex → router.ex → public_document_controller.ex → document_delivery.ex
```

The remaining cycle is acceptable because `PdfRenderer` is:
1. Documented as intentional coupling
2. Isolated to a single module
3. Only used by core contexts that cannot access web controllers

## See Also

- `EdocApi.Pdf` — Low-level PDF generation wrapper
- `EdocApiWeb.PdfTemplates` — HTML template rendering
- `EdocApi.ObanWorkers.PdfGenerationWorker` — Async PDF generation
- `EdocApi.DocumentDelivery` — Email delivery with PDF attachments
