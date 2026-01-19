# EdocApi Codebase Overview

## 1) Summary

**EdocApi** is an Elixir/Phoenix invoice management API for Kazakhstan businesses. It handles:
- User registration/authentication (JWT)
- Company profiles with banking info and regulatory codes (KBE/KNP)
- Invoice lifecycle: create (draft) → issue → PDF generation
- Kazakhstan-specific formatting (BIN/IIN identifiers, KZT currency, Russian-language PDFs)

---

## 2) Main User Flows (API Endpoints)

| Flow | Endpoint | Controller |
|------|----------|------------|
| **Auth** | `POST /v1/auth/signup`, `POST /v1/auth/login` | `lib/edoc_api_web/controllers/auth_controller.ex` |
| **Company** | `GET/PUT /v1/company` | `lib/edoc_api_web/controllers/company_controller.ex` |
| **Bank Accounts** | `GET/POST /v1/company/bank-accounts` | `lib/edoc_api_web/controllers/company_bank_account_controller.ex` |
| **Invoices** | `GET/POST /v1/invoices`, `GET /v1/invoices/:id`, `POST /v1/invoices/:id/issue`, `GET /v1/invoices/:id/pdf` | `lib/edoc_api_web/controllers/invoice_controller.ex` |
| **Contracts** | `GET/POST /v1/contracts` | `lib/edoc_api_web/controllers/contract_controller.ex` |
| **Dictionaries** | `GET /v1/dicts/banks`, `/kbe`, `/knp` | `lib/edoc_api_web/controllers/dict_controller.ex` |

Routes defined in: `lib/edoc_api_web/router.ex`

---

## 3) Core Business Logic

| Context Module | Purpose |
|----------------|---------|
| `lib/edoc_api/invoicing.ex` | **Main logic**: invoice creation, numbering, issuance, bank snapshot capture |
| `lib/edoc_api/accounts.ex` | User registration, authentication (Argon2) |
| `lib/edoc_api/companies.ex` | Company CRUD |
| `lib/edoc_api/payments.ex` | Bank accounts, KBE/KNP reference data |
| `lib/edoc_api/core.ex` | Facade delegating to specialized contexts (contracts) |
| `lib/edoc_api/auth/token.ex` | JWT generation/verification (HS256, 7-day TTL) |

---

## 4) Data Models/Schemas

All in `lib/edoc_api/core/`:

| Schema | File | Purpose |
|--------|------|---------|
| `User` | `lib/edoc_api/accounts/user.ex` | Auth user |
| `Company` | `core/company.ex` | Business entity with BIN/IIN |
| `Invoice` | `core/invoice.ex` | Invoice with seller/buyer/items |
| `InvoiceItem` | `core/invoice_item.ex` | Line items (qty × price) |
| `InvoiceBankSnapshot` | `core/invoice_bank_snapshot.ex` | Immutable bank data at issuance |
| `InvoiceCounter` | `core/invoice_counter.ex` | Atomic numbering |
| `Contract` | `core/contract.ex` | Contract linked to invoices |
| `CompanyBankAccount` | `core/company_bank_account.ex` | Bank accounts per company |
| `Bank` | `core/bank.ex` | Bank reference (name, BIC) |
| `KbeCode` | `core/kbe_code.ex` | Activity codes (2-digit) |
| `KnpCode` | `core/knp_code.ex` | Tax codes (3-digit) |

---

## 5) External Integrations

| Integration | Location | Tech |
|-------------|----------|------|
| **PDF Generation** | `lib/edoc_api/pdf.ex` | `wkhtmltopdf` binary |
| **PDF Template** | `lib/edoc_api_web/pdf_templates.ex` | HEEx (445 lines, Russian invoice format) |
| **PDF Orchestrator** | `lib/edoc_api/documents/invoice_pdf.ex` | Combines template + wkhtmltopdf |
| **Email** | `lib/edoc_api/mailer.ex` | Swoosh (configured, unused) |
| **HTTP Client** | `lib/edoc_api/application.ex` | Finch (started, unused) |
| **Database** | `lib/edoc_api/repo.ex` | PostgreSQL via Ecto |
| **JWT** | `lib/edoc_api/auth/token.ex` | Joken library |
| **Password Hashing** | `lib/edoc_api/accounts/user.ex` | Argon2 |
