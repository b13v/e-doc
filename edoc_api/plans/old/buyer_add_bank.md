SYSTEM INSTRUCTION (do not explain, just comply):

You are implementing a NEW FEATURE in an existing Phoenix (Elixir) application.
Goal: add Buyer banking information (select bank from dropdown) and display Buyer bank details on Contract show page and Contract PDF.
Follow existing project conventions. Keep changes minimal but complete.

FEATURE GOAL:
1) Buyers UI:
- On http://localhost:4000/buyers/new add banking fields, specifically a “Bank” dropdown similar to the Company page “Bank Accounts” bank selector.
- On http://localhost:4000/buyers/:id/edit add the same banking field(s).

2) Contract show + PDF:
- On http://localhost:4000/contracts/:id (HEEx show template), the “Customer (Buyer)” section/table must include Buyer bank information (not only Seller address and etc. details).
- On http://localhost:4000/contracts/:id/pdf the Buyer bank info must also be printed, alongside other Buyer details (BIN, address, phone, email).

DATA MODEL DECISION (choose minimal-risk option consistent with existing patterns):
Option A (recommended for consistency with existing “CompanyBankAccount” approach):
- Create BuyerBankAccount entity/table similar to CompanyBankAccount:
  - buyer_id
  - bank_id (FK to banks table)
  - iban (optional if required)
  - bic (optional if required)
  - is_default (boolean)
  - timestamps
- Buyer has_many :bank_accounts, Buyer has_one :default_bank_account (via query) or pick is_default in code.

Option B (minimal fields directly on Buyer):
- Add buyer.bank_id as FK to banks table (single bank only).
Choose only if you truly want Buyer to have only one bank and no future scaling.

IMPLEMENTATION REQUIREMENTS:
- Bank dropdown list must use the same bank source as Company bank accounts dropdown (reuse the same query/helper).
- Ownership rules: Buyer belongs to Seller’s company, and Buyer bank accounts must be owned through Buyer (no cross-company linking).
- Editing Buyer must preserve existing values.
- Contract show and PDF must load Buyer’s bank data via preloads (similar to how Buyer core details are loaded).

SCOPE (HARD LIMITS):
- Do NOT scan the whole repository
- Do NOT add new dependencies
- Keep changes localized
- Prefer reusing existing patterns/components from Company bank accounts

FILES TO TOUCH (EXPECTED):
- lib/edoc_api/core/buyer.ex
- lib/edoc_api_web/controllers/buyer_controller.ex
- lib/edoc_api_web/templates/buyer/new.html.heex
- lib/edoc_api_web/templates/buyer/edit.html.heex
- lib/edoc_api_web/templates/contract/show.html.heex
- lib/edoc_api_web/controllers/contract_controller.ex (or wherever contract show/pdf is prepared)
- lib/edoc_api/pdf/pdf_templates.ex (or the actual contract PDF template file)
PLUS (if Option A is chosen):
- priv/repo/migrations/*_create_buyer_bank_accounts.exs
- lib/edoc_api/core/buyer_bank_account.ex

RESPONSE FORMAT (STRICT):
1) Plan (max 10 bullets) — explicitly state whether you chose Option A or B and why
2) DB changes (if any) — exact unified diff for migration(s)
3) Schemas/changesets — exact unified diff
4) Buyer controller + templates — exact unified diff (new/edit show bank dropdown, save/load)
5) Contract controller/show template — exact unified diff (preload buyer bank data and display it)
6) Contract PDF template changes — exact unified diff (print buyer bank info)
7) Verification steps:
   - mix ecto.migrate (if applicable)
   - manual UI steps (buyers/new, buyers/:id/edit, contracts/:id)
   - PDF check steps

RULES:
- Provide ONLY unified diffs in sections (2)-(6)
- No markdown, no greetings, no extra commentary
- If you need an additional file not listed above, STOP and output only:
  NEED FILE: <path> (reason: <one sentence>)
- STOP after section (7)
