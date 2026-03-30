SYSTEM INSTRUCTION (do not explain, just comply):

You are implementing a NEW FEATURE in an existing Phoenix (Elixir) application.
Goal: add a “Units of Measurement” classifier (reference table) and use it as a dropdown
instead of free text “Code” in Contract Items (Appendix 1), and display it on the Contract show page table.

SOURCE DATA:
There is an csv file with units at: units_of_measurement.csv
Columns:
- "Код (ОКЕИ)"
- "Условное обозначение"   (this is the dropdown value, e.g. "шт")
- "Полное наименование"
- "Категория / Применение"
Total rows: 24

FEATURE REQUIREMENTS:

1) Create a reference table (dictionary) for Units of Measurement
- Table name: units_of_measurements
- Fields:
  - okei_code (integer) from "Код (ОКЕИ)"
  - symbol (string) from "Условное обозначение"  <-- dropdown value to store/use
  - name (string) from "Полное наименование"
  - category (string) from "Категория / Применение"
  - timestamps
- Add appropriate indexes:
  - unique index on symbol
  - optional unique index on okei_code (if safe)

2) Seed data from the csv file
- Add a one-time seed importer (prefer: priv/repo/seeds.exs or a dedicated mix task)
- It must insert/update units from /mnt/data/units_of_measurement.xlsx
- Idempotent behavior: re-running should not duplicate (use upsert by symbol or okei_code)

3) Contract Items UI: dropdown instead of free text “Code”
Routes/pages:
- http://localhost:4000/contracts/new
- http://localhost:4000/contracts/edit/:id
In the Contract Items (Appendix 1) form/table:
- Replace free input “Code” with a dropdown/select populated from units_of_measurements
- Dropdown label can be: "шт — Штука" (symbol + name), but the stored value must be the symbol (e.g. "шт")
- Existing contract item field in codebase is known as item.code (appears in invoicing.ex, edit/new templates placeholders, and invoices_controller.ex).
For this task, focus on Contract items. Keep impact minimal.

DATA STORAGE DECISION (choose the minimal-risk option consistent with current schema):
Option A (minimal / no breaking migration on contract_items):
- Keep contract_items.code as string
- On save, store selected unit symbol into item.code
- Add validation: code must be one of known unit symbols (optional for MVP if it would break existing data)

Option B (more strict / normalized):
- Add contract_items.unit_of_measurement_id (FK) and deprecate free-text code
- Keep code for backward compatibility and populate it from selected unit.symbol
(Choose only if project conventions already favor FKs for classifiers.)

4) Contract show page table (Appendix 1)
After draft is created (contract show page: /contracts/:id), in Appendix 1 (Спецификация) table:
- Add a new column between “Наименование” and “Кол-во”:
  - Header: “Ед. изм.”
  - Cell value: the selected unit symbol (e.g. "шт")
- Ensure this value displays reliably (either from item.code or from unit relation if you use Option B)

SCOPE (HARD LIMITS):
- Do NOT scan the whole repository
- Do NOT add new dependencies
- Keep changes localized and consistent with existing patterns

FILES TO TOUCH (EXPECTED):
- priv/repo/migrations/*_create_units_of_measurements.exs
- lib/edoc_api/core/unit_of_measurement.ex (new schema)
- priv/repo/seeds.exs (or a new seed importer you reference clearly)
- lib/edoc_api_web/controllers/contract_controller.ex (or whichever controller renders new/edit/show)
- lib/edoc_api_web/templates/contract/new.html.heex (or component used)
- lib/edoc_api_web/templates/contract/edit.html.heex (or component used)
- lib/edoc_api_web/templates/contract/show.html.heex (Appendix 1 table rendering)
- lib/edoc_api/core/contract_item.ex (ONLY if needed to validate/store)

RESPONSE FORMAT (STRICT):
1) Plan (max 10 bullets) stating which storage option you chose (A or B) and why
2) Migration diff (units_of_measurements) — exact unified diff
3) Schema diff (UnitOfMeasurement) — exact unified diff
4) Seed importer diff — exact unified diff (must read /mnt/data/units_of_measurement.xlsx)
5) Contract controller diff — exact unified diff (load units for new/edit; preload for show if needed)
6) HEEx template diffs:
   - new.html.heex / edit.html.heex (dropdown replaces “Code”)
   - show.html.heex (add “Ед. изм.” column)
7) Verification steps:
   - mix ecto.migrate
   - mix run priv/repo/seeds.exs (or your importer command)
   - manual UI steps to confirm dropdown + show table

RULES:
- Provide ONLY unified diffs in sections (2)-(6)
- No markdown, no greetings, no extra commentary
- If you need an additional file not listed, STOP and output only:
  NEED FILE: <path> (reason: <one sentence>)
- STOP after section (7)
