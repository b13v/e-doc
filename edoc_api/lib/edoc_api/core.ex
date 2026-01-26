defmodule EdocApi.Core do
  import Ecto.Query, warn: false

  alias EdocApi.Companies
  alias EdocApi.Invoicing
  alias EdocApi.Payments
  alias EdocApi.Repo
  alias EdocApi.Core.Company
  alias EdocApi.Core.Contract

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

  def list_contracts_for_user(%{id: user_id}), do: list_contracts_for_user(user_id)

  def list_contracts_for_user(user_id) when is_binary(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        []

      %Company{id: company_id} ->
        Contract
        |> where([c], c.company_id == ^company_id)
        |> order_by([c],
          desc: fragment("COALESCE(?, ?)", c.date, fragment("?::date", c.inserted_at)),
          desc: c.inserted_at
        )
        |> Repo.all()
    end
  end

  def create_contract_for_user(%{id: user_id}, attrs),
    do: create_contract_for_user(user_id, attrs)

  def create_contract_for_user(user_id, attrs) when is_binary(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        {:error, :company_required}

      %Company{id: company_id} ->
        attrs = attrs || %{}

        %Contract{}
        |> Contract.changeset(attrs, company_id)
        |> Repo.insert()
    end
  end

  def get_contract_for_user(%{id: user_id}, contract_id),
    do: get_contract_for_user(user_id, contract_id)

  def get_contract_for_user(user_id, contract_id) when is_binary(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        {:error, :not_found}

      %Company{id: company_id} ->
        Contract
        |> where([c], c.company_id == ^company_id and c.id == ^contract_id)
        |> Repo.one()
        |> case do
          nil -> {:error, :not_found}
          contract -> {:ok, contract}
        end
    end
  end
end
