# Phoenix Patterns Research: PDF Template Solutions

## Recommended Approach: Phoenix.Template.embed_templates/2

Instead of dependency injection, move HTML templates into core domain using Phoenix's built-in template embedding.

### Why This Is Phoenix-Idiomatic

- ✅ Follows Phoenix.Template pattern (like Swoosh email templates)
- ✅ PDFs are business logic, not web presentation
- ✅ Works cleanly with background jobs
- ✅ No web context needed for rendering
- ✅ Testable without Phoenix stack

### Implementation

```elixir
# NEW: lib/edoc_api/documents/templates.ex
defmodule EdocApi.Documents.Templates do
  require EEx
  embed_templates "templates", suffix: "_html"

  def contract_html(contract) do
    contract = Repo.preload(contract, [
      :company, :bank_account, :contract_items,
      buyer: [bank_accounts: :bank],
      bank_account: [:bank, :kbe_code, :knp_code]
    ])
    
    assigns = build_assigns(contract)
    contract_html(assigns)
  end

  defp build_assigns(contract) do
    %{
      contract: contract,
      seller: build_seller_data(contract),
      buyer: build_buyer_data(contract),
      bank: build_bank_data(contract),
      items: build_items_data(contract),
      totals: build_totals(contract.contract_items, contract.vat_rate)
    }
  end
end

# NEW: lib/edoc_api/documents/templates/contract.html.eex
<!DOCTYPE html>
<html>
<head>...</head>
<body><%= @contract.number %></body>
</html>

# UPDATED: lib/edoc_api/documents/contract_pdf.ex
defmodule EdocApi.Documents.ContractPdf do
  alias EdocApi.Documents.Templates  # ✅ Core → Core only
  
  def render(contract) do
    contract
    |> Templates.contract_html()
    |> Pdf.html_to_pdf()
  end
end
```

### Alternative: Dependency Injection (Original Plan)

Pass pre-rendered HTML from web layer to PDF modules.

| Approach | Pros | Cons |
|----------|------|------|
| embed_templates | Self-contained, testable | Templates live in core |
| Dependency injection | Clean separation | Controllers know about HTML |

Both are valid. Choose based on whether PDF generation is "core domain" (embed_templates) or "infrastructure" (dependency injection).
