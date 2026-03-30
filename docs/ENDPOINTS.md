# List of API Endpoints (routes/controllers)

| Endpoint | Controller (file) | Context/Service (file) | Schema/Repo calls |
|---|---|---|---|
| `GET /v1/health` | `EdocApiWeb.HealthController` (`edoc_api/lib/edoc_api_web/controllers/heath_controller.ex`) | — | — |
| `POST /v1/auth/signup` | `EdocApiWeb.AuthController` (`edoc_api/lib/edoc_api_web/controllers/auth_controller.ex`) | `EdocApi.Accounts.register_user/1` (`edoc_api/lib/edoc_api/accounts.ex`), `EdocApi.Auth.Token.generate_access_token/1` (`edoc_api/lib/edoc_api/auth/token.ex`) | `EdocApi.Accounts.User` (`edoc_api/lib/edoc_api/accounts/user.ex`) + `EdocApi.Repo` |
| `POST /v1/auth/login` | `EdocApiWeb.AuthController` (`edoc_api/lib/edoc_api_web/controllers/auth_controller.ex`) | `EdocApi.Accounts.authenticate_user/2` (`edoc_api/lib/edoc_api/accounts.ex`), `EdocApi.Auth.Token.generate_access_token/1` | `EdocApi.Accounts.User` + `EdocApi.Repo` |
| `GET /v1/company` | `EdocApiWeb.CompanyController` (`edoc_api/lib/edoc_api_web/controllers/company_controller.ex`) | `EdocApi.Companies.get_company_by_user_id/1` (`edoc_api/lib/edoc_api/companies.ex`) | `EdocApi.Core.Company` (`edoc_api/lib/edoc_api/core/company.ex`) + `EdocApi.Repo` |
| `PUT /v1/company` | `EdocApiWeb.CompanyController` | `EdocApi.Companies.upsert_company_for_user/2` | `EdocApi.Core.Company` + `EdocApi.Repo` |
| `GET /v1/invoices` | `EdocApiWeb.InvoiceController` (`edoc_api/lib/edoc_api_web/controllers/invoice_controller.ex`) | `EdocApi.Invoicing.list_invoices_for_user/1` (`edoc_api/lib/edoc_api/invoicing.ex`) | `EdocApi.Core.Invoice`, `EdocApi.Core.InvoiceItem`, `EdocApi.Core.Company` + `EdocApi.Repo` |
| `POST /v1/invoices` | `EdocApiWeb.InvoiceController` | `EdocApi.Invoicing.create_invoice_for_user/3` | `EdocApi.Core.Invoice`, `EdocApi.Core.InvoiceItem`, `EdocApi.Core.InvoiceCounter`, `EdocApi.Core.Company` + `EdocApi.Repo` |
| `GET /v1/invoices/:id` | `EdocApiWeb.InvoiceController` | `EdocApi.Invoicing.get_invoice_for_user/2` | `EdocApi.Core.Invoice` + `EdocApi.Repo` |
| `POST /v1/invoices/:id/issue` | `EdocApiWeb.InvoiceController` | `EdocApi.Invoicing.issue_invoice_for_user/2` → `mark_invoice_issued/1` | `EdocApi.Core.Invoice` + `EdocApi.Repo` |
| `GET /v1/invoices/:id/pdf` | `EdocApiWeb.InvoiceController` | `EdocApi.Invoicing.get_invoice_for_user/2` + `EdocApi.Documents.InvoicePdf.render/1` (`edoc_api/lib/edoc_api/documents/invoice_pdf.ex`) | `EdocApi.Core.Invoice` + `EdocApi.Repo`; PDF uses `EdocApiWeb.PdfTemplates` + `EdocApi.Pdf` |
| `GET /v1/dicts/banks` | `EdocApiWeb.DictController` (`edoc_api/lib/edoc_api_web/controllers/dict_controller.ex`) | `EdocApi.Payments.list_banks/0` (`edoc_api/lib/edoc_api/payments.ex`) | `EdocApi.Core.Bank` (`edoc_api/lib/edoc_api/core/bank.ex`) + `EdocApi.Repo` |
| `GET /v1/dicts/kbe` | `EdocApiWeb.DictController` | `EdocApi.Payments.list_kbe_codes/0` | `EdocApi.Core.KbeCode` (`edoc_api/lib/edoc_api/core/kbe_code.ex`) + `EdocApi.Repo` |
| `GET /v1/dicts/knp` | `EdocApiWeb.DictController` | `EdocApi.Payments.list_knp_codes/0` | `EdocApi.Core.KnpCode` (`edoc_api/lib/edoc_api/core/knp_code.ex`) + `EdocApi.Repo` |
| `GET /v1/company/bank-accounts` | `EdocApiWeb.CompanyBankAccountController` (`edoc_api/lib/edoc_api_web/controllers/company_bank_account_controller.ex`) | `EdocApi.Payments.list_company_bank_accounts_for_user/1` | `EdocApi.Core.CompanyBankAccount` + `EdocApi.Repo` |
| `POST /v1/company/bank-accounts` | `EdocApiWeb.CompanyBankAccountController` | `EdocApi.Payments.create_company_bank_account_for_user/2` | `EdocApi.Core.CompanyBankAccount` + `EdocApi.Repo` |
