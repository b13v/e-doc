# EdocApi Repository Summary

## 1) Application Summary

**EdocApi** is an Elixir/Phoenix e-document management API for Kazakhstan businesses. It handles invoice generation, contract management, and PDF document creation with support for Kazakhstan-specific tax requirements (VAT 16%, BIN/IIN validation, KBE/KNP payment codes). The app provides both a JSON API and an HTML/HTMX web interface.

---

## 2) Main User Flows

### Authentication Flows

| Endpoint               | Controller       | Action   |
| ---------------------- | ---------------- | -------- |
| `POST /v1/auth/signup` | `AuthController` | `signup` |
| `POST /v1/auth/login`  | `AuthController` | `login`  |

### Invoice Management Flows

| Endpoint                      | Controller          | Action   | Description           |
| ----------------------------- | ------------------- | -------- | --------------------- |
| `GET /v1/invoices`            | `InvoiceController` | `index`  | List user invoices    |
| `POST /v1/invoices`           | `InvoiceController` | `create` | Create draft invoice  |
| `GET /v1/invoices/:id`        | `InvoiceController` | `show`   | Get invoice details   |
| `PUT /v1/invoices/:id`        | `InvoiceController` | `update` | Update draft invoice  |
| `POST /v1/invoices/:id/issue` | `InvoiceController` | `issue`  | Finalize/lock invoice |
| `GET /v1/invoices/:id/pdf`    | `InvoiceController` | `pdf`    | Generate PDF          |

### Contract Management Flows

| Endpoint                       | Controller           | Action   |
| ------------------------------ | -------------------- | -------- |
| `GET /v1/contracts`            | `ContractController` | `index`  |
| `POST /v1/contracts`           | `ContractController` | `create` |
| `GET /v1/contracts/:id`        | `ContractController` | `show`   |
| `POST /v1/contracts/:id/issue` | `ContractController` | `issue`  |
| `GET /v1/contracts/:id/pdf`    | `ContractController` | `pdf`    |

### Company & Bank Account Flows

| Endpoint                                        | Controller                     | Description           |
| ----------------------------------------------- | ------------------------------ | --------------------- |
| `GET /v1/company`                               | `CompanyController`            | Get company profile   |
| `PUT /v1/company`                               | `CompanyController`            | Create/update company |
| `GET /v1/company/bank-accounts`                 | `CompanyBankAccountController` | List accounts         |
| `POST /v1/company/bank-accounts`                | `CompanyBankAccountController` | Add account           |
| `PUT /v1/company/bank-accounts/:id/set-default` | `CompanyBankAccountController` | Set default           |

### Dictionary/Reference Data

| Endpoint              | Controller       | Data                  |
| --------------------- | ---------------- | --------------------- |
| `GET /v1/dicts/banks` | `DictController` | Kazakhstan banks list |
| `GET /v1/dicts/kbe`   | `DictController` | KBE payment codes     |
| `GET /v1/dicts/knp`   | `DictController` | KNP payment codes     |

---

## 3) Core Business Logic

Located in **Context modules** under `lib/edoc_api/`:

| Module                   | File                              | Responsibility                                                                  |
| ------------------------ | --------------------------------- | ------------------------------------------------------------------------------- |
| `EdocApi.Invoicing`      | `lib/edoc_api/invoicing.ex`       | Invoice CRUD, issuance, auto-numbering, VAT calculation, bank snapshot creation |
| `EdocApi.Core`           | `lib/edoc_api/core.ex`            | Contract management, aggregates company/invoice/bank operations                 |
| `EdocApi.Accounts`       | `lib/edoc_api/accounts.ex`        | User registration, authentication with Argon2                                   |
| `EdocApi.Companies`      | `lib/edoc_api/companies.ex`       | Company profile management                                                      |
| `EdocApi.Payments`       | `lib/edoc_api/payments.ex`        | Bank accounts, KBE/KNP code management                                          |
| `EdocApi.VatRates`       | `lib/edoc_api/vat_rates.ex`       | VAT calculation (KZ: 0%, 16%), currency rounding                                |
| `EdocApi.Currencies`     | `lib/edoc_api/currencies.ex`      | Currency precision handling                                                     |
| `EdocApi.InvoiceStatus`  | `lib/edoc_api/invoice_status.ex`  | State machine for invoice lifecycle                                             |
| `EdocApi.ContractStatus` | `lib/edoc_api/contract_status.ex` | Contract state management                                                       |

---

## 4) Data Models/Schemas

Located in `lib/edoc_api/core/` and `lib/edoc_api/accounts/`:

| Model                              | File                                         | Description                                              |
| ---------------------------------- | -------------------------------------------- | -------------------------------------------------------- |
| `EdocApi.Accounts.User`            | `lib/edoc_api/accounts/user.ex`              | User authentication (email, password_hash)               |
| `EdocApi.Core.Company`             | `lib/edoc_api/core/company.ex`               | Company profile (name, BIN/IIN, address, representative) |
| `EdocApi.Core.Invoice`             | `lib/edoc_api/core/invoice.ex`               | Invoice with seller/buyer snapshot fields                |
| `EdocApi.Core.InvoiceItem`         | `lib/edoc_api/core/invoice_item.ex`          | Line items for invoices                                  |
| `EdocApi.Core.Contract`            | `lib/edoc_api/core/contract.ex`              | Legal contracts with buyer details                       |
| `EdocApi.Core.ContractItem`        | `lib/edoc_api/core/contract_item.ex`         | Line items for contracts                                 |
| `EdocApi.Core.CompanyBankAccount`  | `lib/edoc_api/core/company_bank_account.ex`  | Bank accounts with IBAN, KBE/KNP codes                   |
| `EdocApi.Core.Bank`                | `lib/edoc_api/core/bank.ex`                  | Kazakhstan banks reference data                          |
| `EdocApi.Core.KbeCode`             | `lib/edoc_api/core/kbe_code.ex`              | KBE payment classification codes                         |
| `EdocApi.Core.KnpCode`             | `lib/edoc_api/core/knp_code.ex`              | KNP payment purpose codes                                |
| `EdocApi.Core.InvoiceCounter`      | `lib/edoc_api/core/invoice_counter.ex`       | Auto-numbering sequence per company                      |
| `EdocApi.Core.InvoiceBankSnapshot` | `lib/edoc_api/core/invoice_bank_snapshot.ex` | Frozen bank details at issuance time                     |

---

## 5) External Integrations

| Integration          | Module                          | File                                     | Details                                        |
| -------------------- | ------------------------------- | ---------------------------------------- | ---------------------------------------------- |
| **PDF Generation**   | `EdocApi.Pdf`                   | `lib/edoc_api/pdf.ex`                    | Uses `wkhtmltopdf` CLI for HTML→PDF conversion |
| **PDF Templates**    | `EdocApi.Documents.InvoicePdf`  | `lib/edoc_api/documents/invoice_pdf.ex`  | Invoice PDF generation                         |
| **PDF Templates**    | `EdocApi.Documents.ContractPdf` | `lib/edoc_api/documents/contract_pdf.ex` | Contract PDF generation                        |
| **Email**            | `EdocApi.Mailer`                | `lib/edoc_api/mailer.ex`                 | Swoosh email adapter (currently Local adapter) |
| **Authentication**   | `EdocApi.Auth.Token`            | `lib/edoc_api/auth/token.ex`             | JWT token generation (Joken library)           |
| **Password Hashing** | -                               | -                                        | Argon2 via `argon2_elixir`                     |
| **Database**         | `EdocApi.Repo`                  | `lib/edoc_api/repo.ex`                   | PostgreSQL via Ecto                            |

### Dependencies (from `mix.exs`):

- **Web**: Phoenix 1.7, Phoenix Ecto
- **Auth**: Argon2, Joken (JWT)
- **Database**: Ecto SQL, Postgrex
- **Email**: Swoosh, Finch (HTTP client)
- **PDF**: External `wkhtmltopdf` binary
- **Validation**: Custom validators in `lib/edoc_api/validators/` (BIN/IIN, Email, IBAN)
