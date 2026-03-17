SYSTEM INSTRUCTION (do not explain, just comply):

You are implementing a UI FEATURE / SIMPLIFICATION in an existing Phoenix (Elixir) application.
Goal: simplify Company Bank Accounts UI by removing KBE/KNP fields and adding View/Edit actions.
Keep changes minimal and consistent with existing patterns.

FEATURE GOAL:
On http://localhost:4000/company (Company page):
1) When adding/editing Bank Accounts:
- Remove fields “KBE Code” and “KNP Code” from the HEEx template.
- The form must have ONLY these fields:
  - Label (text)
  - Bank (dropdown/select)
  - IBAN (text input)

2) Bank Accounts table (at bottom of the same page):
- Currently columns include: Label, Bank, IBAN, KBE, KNP, DEFAULT, ACTIONS
- Remove KBE and KNP columns entirely.
- Update ACTIONS column to include:
  - “View” (goes to a view page for a bank account)
  - “Edit” (goes to an edit page for a bank account)
- Implement the corresponding routes/controller actions/templates for viewing and editing a bank account.

SCOPE (HARD LIMITS):
- Do NOT scan the whole repository
- Do NOT add new dependencies
- Do NOT change DB schema/migrations (keep kbe_code_id/knp_code_id in DB as-is; just remove from UI)
- Keep changes localized to company/bank account UI flow

ASSUMPTIONS:
- The app already has a banks reference list used in a dropdown.
- CompanyBankAccount model may still store KBE/KNP in DB; UI simply stops exposing them.
- “View” and “Edit” should enforce ownership (only the logged-in user’s company can view/edit).

FILES TO TOUCH (EXPECTED):
- lib/edoc_api_web/router.ex
- lib/edoc_api_web/controllers/company_controller.ex (if company page logic is here)
- lib/edoc_api_web/controllers/company_bank_account_controller.ex (or equivalent)
- lib/edoc_api_web/templates/company/show.html.heex (or the actual /company template)
- lib/edoc_api_web/templates/company_bank_account/show.html.heex (new or existing)
- lib/edoc_api_web/templates/company_bank_account/edit.html.heex (new or existing)
- lib/edoc_api_web/templates/company_bank_account/form.html.heex (if shared)
(Optional only if needed)
- lib/edoc_api/core/company_bank_account.ex (only if changeset requires making kbe/knp optional and currently blocks saving)

ROUTING REQUIREMENTS (inside auth scope, consistent with existing /v1 or HTML routes):
- Add routes for HTML view/edit of bank accounts, e.g.:
  - GET  /company/bank-accounts/:id      CompanyBankAccountController, :show
  - GET  /company/bank-accounts/:id/edit CompanyBankAccountController, :edit
  - PUT  /company/bank-accounts/:id      CompanyBankAccountController, :update
(Use existing naming/route conventions in the project; if there is already a resource route, extend it.)

FORM REQUIREMENTS:
- The edit form must show only: Label, Bank dropdown, IBAN
- On update, preserve existing kbe_code_id/knp_code_id values in DB (do not nil them unless necessary)
- View page should display Label, Bank, IBAN, and Default status (KBE/KNP hidden)

RESPONSE FORMAT (STRICT):
1) Plan (max 8 bullets)
2) Router changes (exact unified diff)
3) Controller changes (exact unified diff)
4) Company page template changes (exact unified diff) — remove KBE/KNP fields + remove KBE/KNP columns + add View/Edit links
5) Bank account show/edit templates (exact unified diff)
6) Verification steps:
   - manual UI flow on /company: add bank account, see table, click View/Edit, update IBAN
   - ensure no KBE/KNP fields appear

RULES:
- Provide ONLY unified diffs in sections (2)-(5)
- No markdown, no greetings, no extra commentary
- If you need an additional file not listed above, STOP and output only:
  NEED FILE: <path> (reason: <one sentence>)
- STOP after section (6)
