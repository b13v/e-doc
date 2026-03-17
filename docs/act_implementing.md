SYSTEM INSTRUCTION (do not explain, just comply):

You are implementing a NEW FEATURE in an existing Phoenix (Elixir) application (edoc_api).
Feature: “Act of Performed Works / Rendered Services” (Акт выполненных работ / оказанных услуг) — Kazakhstan/CIS-specific document type.
Deliver an end-to-end change: data model (if needed) → create flow UI (HEEx) → PDF template (HEEx/HTML) using the provided Excel as the exact layout reference.

REFERENCE FILE (LAYOUT SOURCE):
Use this Excel file as the single source of truth for the Act layout and static text lines:
- /mnt/data/1215.QWS.Алюминий.Изоляция.АВР.13..260206.xls
Your HEEx template + PDF HTML must match the structure/rows/labels from this file.

FEATURE REQUIREMENTS:

A) Create Act UI (similar to invoices/new)
Route/page reference for UX patterns: http://localhost:4000/invoices/new
New pages to implement (or equivalents in your routing style):
- GET  /acts/new
- POST /acts
- GET  /acts/:id
- GET  /acts/:id/pdf

Two creation modes:

1) From Contract
- User selects a Contract from dropdown (ONLY status == "issued", owned by user/company)
- Selecting contract prepopulates Buyer details (and items from Contract Appendix 1)
- Required fields: issue_date, due_date, actual_date, items
- Other fields (bank account, KBE, KNP, etc.) are NOT required for Act

2) Direct (No Contract)
- Required fields: buyer (dropdown), buyer_address (autofill from Buyer table), issue_date, due_date, items
- actual_date optional but supported (can be blank)

B) Act fields mapping (must exist in HEEx template and PDF template)
3.1 Document number: auto-generated
3.2 “Дата составления” = issue_date
3.3 “Дата подписания (принятия)работ(услуг)” = actual_date
3.4 “Заказчик” = Company name + address + phone
3.5 IIN/BIN fields: from company and buyer respectively
3.6 “Договор (контракт)” = contract number/date if created from contract; otherwise blank or “—”
Table columns MUST match Excel layout and include:
3.7 “Номер по порядку” = row index
3.8 Description = items (from contract or manual)
3.9 “Дата выполнения работ/услуг” = actual_date (or blank per row if your model supports row-level actual date; MVP can use one shared actual_date)
3.10 “Сведения об отчете …” = usually empty (keep column, allow blank)
3.11 “Единица измерения” = units of measurement (use your units_of_measurements dictionary; store symbol like “шт”, “услуга”, etc.)
3.13 Quantity
3.14 Unit price (price incl. VAT)
3.15 Cost (total incl. VAT)
3.16 VAT amount (in KZT) per line
Below the table:
- “Итого” row:
  - total quantity in the quantity column
  - put “x” in unit price column
  - total cost in cost column
  - total VAT in VAT column

C) Template requirements
- HEEx template for creating/editing Act must be based on the Excel layout (rows/labels/sections).
- PDF template must also follow Excel layout and static lines “as in the Excel file”.
- Use placeholders or “—” where optional data is absent.

D) Minimal data model (choose the smallest viable design)
You must decide and implement one of the following, consistent with existing Invoice/Contract patterns:

Option A (recommended):
- Create Act entity/table: acts
- Create ActItem table similar to invoice_items/contract_items
- Act has optional contract_id, required buyer_id, required company_id, status (draft/issued/signed), issue_date, due_date, actual_date
- Act has_many :items

Option B (only if your app already reuses invoice_items in a clean way):
- Reuse existing items table via polymorphic approach (not recommended unless already present)

Also ensure ownership validation:
- buyer_id must belong to company
- contract_id (if present) must belong to company AND be issued

SCOPE (HARD LIMITS):
- Do NOT scan the whole repository
- Do NOT add new dependencies
- Keep changes localized and consistent with existing patterns (Invoices/Contracts)
- If you need JS for dynamic prefill, prefer server-driven approach:
  GET /acts/new?contract_id=... reload to prefill (minimal + reliable)

FILES TO TOUCH (EXPECTED):
- priv/repo/migrations/*_create_acts.exs
- priv/repo/migrations/*_create_act_items.exs
- lib/edoc_api/core/act.ex
- lib/edoc_api/core/act_item.ex
- lib/edoc_api/core.ex or lib/edoc_api/acts.ex (context functions: list_issued_contracts_for_user, build_act_from_contract, create_act_for_user, get_act_for_user)
- lib/edoc_api_web/router.ex
- lib/edoc_api_web/controllers/act_controller.ex
- lib/edoc_api_web/templates/act/new.html.heex
- lib/edoc_api_web/templates/act/show.html.heex
- lib/edoc_api/pdf/pdf_templates.ex (or your actual PDF HTML template module for acts)

RESPONSE FORMAT (STRICT):
1) Plan (max 12 bullets) — state which data model option you chose and why
2) Schema/migrations diffs (exact unified diff)
3) Core/context diffs (exact unified diff)
4) Router + Controller diffs (exact unified diff)
5) HEEx templates diffs:
   - new.html.heex (create flow with two modes + required fields)
   - show.html.heex (render draft view matching Excel sections)
6) PDF template diff (exact unified diff) — layout/rows/labels must match the Excel file
7) Verification steps:
   - mix ecto.migrate
   - manual steps for both flows (From Contract / Direct)
   - PDF check steps (/acts/:id/pdf)

RULES:
- Provide ONLY unified diffs in sections (2)-(6)
- No markdown, no greetings, no extra commentary
- If you need an additional file not listed above, STOP and output only:
  NEED FILE: <path> (reason: <one sentence>)
- STOP after section (7)
