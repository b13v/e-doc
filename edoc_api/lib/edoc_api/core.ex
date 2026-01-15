defmodule EdocApi.Core do
  alias EdocApi.Companies
  alias EdocApi.Invoicing
  alias EdocApi.Payments

  defdelegate get_company_by_user_id(user_id), to: Companies
  defdelegate upsert_company_for_user(user_id, attrs), to: Companies

  defdelegate list_company_bank_accounts_for_user(user_id), to: Payments
  defdelegate create_company_bank_account_for_user(user_id, attrs), to: Payments
  defdelegate list_banks(), to: Payments
  defdelegate list_kbe_codes(), to: Payments
  defdelegate list_knp_codes(), to: Payments

  defdelegate get_invoice_for_user(user_id, invoice_id), to: Invoicing
  defdelegate list_invoices_for_user(user_id), to: Invoicing
  defdelegate issue_invoice_for_user(user_id, invoice_id), to: Invoicing
  defdelegate create_invoice_for_user(user_id, company_id, attrs), to: Invoicing
  defdelegate next_invoice_number!(company_id), to: Invoicing
  defdelegate mark_invoice_issued(invoice), to: Invoicing
end
