# Architecture

## Summary
EdocApi is a Phoenix JSON API for managing companies and invoices, issuing invoices, and generating invoice PDFs. Authentication uses JWT, and data is stored in Postgres via Ecto.

## Project Map
### API Endpoints (router)
- Public
  - `GET /v1/health` → `EdocApiWeb.HealthController` (`edoc_api/lib/edoc_api_web/controllers/heath_controller.ex`)
  - `POST /v1/auth/signup` → `EdocApiWeb.AuthController` (`edoc_api/lib/edoc_api_web/controllers/auth_controller.ex`)
  - `POST /v1/auth/login` → `EdocApiWeb.AuthController` (`edoc_api/lib/edoc_api_web/controllers/auth_controller.ex`)
- Protected (JWT)
  - `GET /v1/company` / `PUT /v1/company` → `EdocApiWeb.CompanyController` (`edoc_api/lib/edoc_api_web/controllers/company_controller.ex`)
  - `GET /v1/invoices` / `POST /v1/invoices` / `GET /v1/invoices/:id` → `EdocApiWeb.InvoiceController` (`edoc_api/lib/edoc_api_web/controllers/invoice_controller.ex`)
  - `POST /v1/invoices/:id/issue` → `EdocApiWeb.InvoiceController`
  - `GET /v1/invoices/:id/pdf` → `EdocApiWeb.InvoiceController` + `EdocApiWeb.PdfTemplates` (`edoc_api/lib/edoc_api_web/pdf_templates.ex`)
  - `GET /v1/dicts/banks|kbe|knp` → `EdocApiWeb.DictController` (`edoc_api/lib/edoc_api_web/controllers/dict_controller.ex`)
  - `GET /v1/company/bank-accounts` / `POST /v1/company/bank-accounts` → `EdocApiWeb.CompanyBankAccountController` (`edoc_api/lib/edoc_api_web/controllers/company_bank_account_controller.ex`)

Routes live in `edoc_api/lib/edoc_api_web/router.ex` and auth is enforced by `EdocApiWeb.Plugs.Authenticate` (`edoc_api/lib/edoc_api_web/plugs/authenticate.ex`).

### Core Business Logic
- `EdocApi.Core` (`edoc_api/lib/edoc_api/core.ex`)
  - Company upsert + warnings
  - Invoice creation, listing, issuing
  - Invoice number sequencing
  - Company bank accounts + dictionaries
- PDF generation: `EdocApi.Pdf` (`edoc_api/lib/edoc_api/pdf.ex`) + HTML template `EdocApiWeb.PdfTemplates`
- Auth / JWT: `EdocApi.Auth.Token` (`edoc_api/lib/edoc_api/auth/token.ex`)

### Core Domain (by subdomain)
- Invoicing
  - `EdocApi.Core` (`edoc_api/lib/edoc_api/core.ex`): invoice creation/issuing rules, invoice listing
  - `EdocApi.Core.Invoice` (`edoc_api/lib/edoc_api/core/invoice.ex`): invoice schema + totals/status/currency/VAT validation
  - `EdocApi.Core.InvoiceItem` (`edoc_api/lib/edoc_api/core/invoice_item.ex`): line items schema + amount computation
  - `EdocApi.Core.InvoiceCounter` (`edoc_api/lib/edoc_api/core/invoice_counter.ex`): per-company numbering sequence
- Companies
  - `EdocApi.Core.Company` (`edoc_api/lib/edoc_api/core/company.ex`): company schema + validation/normalization + warnings
- Payments & Banking
  - `EdocApi.Core.Bank` (`edoc_api/lib/edoc_api/core/bank.ex`): bank dictionary (name/BIC)
  - `EdocApi.Core.KbeCode` (`edoc_api/lib/edoc_api/core/kbe_code.ex`): KBE code dictionary
  - `EdocApi.Core.KnpCode` (`edoc_api/lib/edoc_api/core/knp_code.ex`): KNP code dictionary
  - `EdocApi.Core.CompanyBankAccount` (`edoc_api/lib/edoc_api/core/company_bank_account.ex`): company bank accounts (IBAN, bank/KBE/KNP refs, default flag)
- Identity & Auth
  - `EdocApi.Accounts` (`edoc_api/lib/edoc_api/accounts.ex`): registration/auth service layer
  - `EdocApi.Accounts.User` (`edoc_api/lib/edoc_api/accounts/user.ex`): user schema + password hashing/validation
  - `EdocApi.Auth.Token` (`edoc_api/lib/edoc_api/auth/token.ex`): JWT issuance/verification rules
- Document Rendering
  - `EdocApi.Pdf` (`edoc_api/lib/edoc_api/pdf.ex`): PDF generation service
  - `EdocApiWeb.PdfTemplates` (`edoc_api/lib/edoc_api_web/pdf_templates.ex`): invoice HTML template (used by PDF)

### Domain Dependency Map (high level)
- Web controllers → `EdocApi.Core` / `EdocApi.Accounts` / `EdocApi.Auth.Token`
- `EdocApi.Core` → Ecto schemas (`Company`, `Invoice`, `InvoiceItem`, `InvoiceCounter`, `Bank`, `KbeCode`, `KnpCode`, `CompanyBankAccount`)
- `EdocApi.Core` → `EdocApi.Repo` (persistence) and `EdocApi.Pdf`/`EdocApiWeb.PdfTemplates` for PDF rendering
- `EdocApi.Accounts` → `EdocApi.Accounts.User` + `EdocApi.Repo` + Argon2
- `EdocApi.Auth.Token` → Joken (JWT)

### Domain Boundaries (schema vs context vs service)
- Invoices
  - Schema: `EdocApi.Core.Invoice` (`edoc_api/lib/edoc_api/core/invoice.ex`), `EdocApi.Core.InvoiceItem` (`edoc_api/lib/edoc_api/core/invoice_item.ex`), `EdocApi.Core.InvoiceCounter` (`edoc_api/lib/edoc_api/core/invoice_counter.ex`)
  - Context: `EdocApi.Core` (`edoc_api/lib/edoc_api/core.ex`)
  - Service: `EdocApi.Pdf` (`edoc_api/lib/edoc_api/pdf.ex`) + `EdocApiWeb.PdfTemplates` (`edoc_api/lib/edoc_api_web/pdf_templates.ex`)
- Companies
  - Schema: `EdocApi.Core.Company` (`edoc_api/lib/edoc_api/core/company.ex`)
  - Context: `EdocApi.Core` (`edoc_api/lib/edoc_api/core.ex`)
  - Service: none (normalization/validation lives in schema)
- Banks & Company Bank Accounts
  - Schema: `EdocApi.Core.Bank` (`edoc_api/lib/edoc_api/core/bank.ex`), `EdocApi.Core.CompanyBankAccount` (`edoc_api/lib/edoc_api/core/company_bank_account.ex`)
  - Context: `EdocApi.Core` (`edoc_api/lib/edoc_api/core.ex`)
  - Service: none
- Reference Dictionaries (KBE/KNP)
  - Schema: `EdocApi.Core.KbeCode` (`edoc_api/lib/edoc_api/core/kbe_code.ex`), `EdocApi.Core.KnpCode` (`edoc_api/lib/edoc_api/core/knp_code.ex`)
  - Context: `EdocApi.Core` (`edoc_api/lib/edoc_api/core.ex`)
  - Service: none

### Web Layer Business Logic (to isolate)
- `EdocApiWeb.InvoiceController` (`edoc_api/lib/edoc_api_web/controllers/invoice_controller.ex`)
  - `invoice_json/1`, `item_json/1` are presentation/serialization concerns.
  - `pdf/2` invokes HTML rendering; consider moving PDF orchestration to a domain service.
- `EdocApiWeb.CompanyBankAccountController` (`edoc_api/lib/edoc_api_web/controllers/company_bank_account_controller.ex`)
  - `bank_account_json/1` is response shaping.
- `EdocApiWeb.DictController` (`edoc_api/lib/edoc_api_web/controllers/dict_controller.ex`)
  - `bank_json/1`, `code_json/1` are response shaping.

### Data Models (Ecto Schemas)
- `EdocApi.Accounts.User` (`edoc_api/lib/edoc_api/accounts/user.ex`)
- `EdocApi.Core.Company` (`edoc_api/lib/edoc_api/core/company.ex`)
- `EdocApi.Core.Invoice` (`edoc_api/lib/edoc_api/core/invoice.ex`)
- `EdocApi.Core.InvoiceItem` (`edoc_api/lib/edoc_api/core/invoice_item.ex`)
- `EdocApi.Core.InvoiceCounter` (`edoc_api/lib/edoc_api/core/invoice_counter.ex`)
- `EdocApi.Core.Bank` (`edoc_api/lib/edoc_api/core/bank.ex`)
- `EdocApi.Core.CompanyBankAccount` (`edoc_api/lib/edoc_api/core/company_bank_account.ex`)
- `EdocApi.Core.KbeCode` / `EdocApi.Core.KnpCode` (`edoc_api/lib/edoc_api/core/kbe_code.ex`, `edoc_api/lib/edoc_api/core/knp_code.ex`)

Migrations: `edoc_api/priv/repo/migrations/*`

### External Integrations
- Postgres via Ecto: `EdocApi.Repo` (`edoc_api/lib/edoc_api/repo.ex`)
- JWT via Joken: `EdocApi.Auth.Token`
- Password hashing via Argon2: `EdocApi.Accounts`
- PDF rendering via `wkhtmltopdf`: `EdocApi.Pdf`
- Mailer (Swoosh): `EdocApi.Mailer` (`edoc_api/lib/edoc_api/mailer.ex`)

## Key Flows
- Auth: signup/login → JWT → `EdocApiWeb.Plugs.Authenticate` attaches `current_user`
- Invoices: create → items + totals computed → issue → status transition → PDF generation
- Companies: upsert → validation + normalization → returned with warnings
