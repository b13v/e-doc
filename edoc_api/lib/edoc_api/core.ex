defmodule EdocApi.Core do
  import Ecto.Query, warn: false

  alias EdocApi.Companies
  alias EdocApi.Errors
  alias EdocApi.Invoicing
  alias EdocApi.Payments
  alias EdocApi.Repo
  alias EdocApi.RepoHelpers
  alias EdocApi.Core.Company
  alias EdocApi.Core.Contract
  alias EdocApi.ContractStatus

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
          desc: fragment("COALESCE(?, ?)", c.issue_date, fragment("?::date", c.inserted_at)),
          desc: c.inserted_at
        )
        |> Repo.all()
    end
  end

  def create_contract_for_user(%{id: user_id}, attrs),
    do: create_contract_for_user(user_id, attrs)

  def create_contract_for_user(user_id, attrs, items_attrs \\ [])
      when is_binary(user_id) and is_list(items_attrs) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        Errors.business_rule(:company_required, %{user_id: user_id})

      %Company{id: company_id} ->
        attrs = attrs || %{}

        RepoHelpers.transaction(fn ->
          %Contract{}
          |> Contract.changeset(attrs, company_id)
          |> RepoHelpers.insert_or_abort()
          |> then(fn contract ->
            if Enum.empty?(items_attrs) do
              {:ok, contract}
            else
              create_contract_items(contract, items_attrs)
            end
          end)
        end)
        |> Errors.normalize()
    end
  end

  def update_contract_for_user(user_id, contract_id, attrs, items_attrs \\ [])
      when is_binary(user_id) and is_list(items_attrs) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        Errors.not_found(:company)

      %Company{id: company_id} ->
        contract =
          Contract
          |> where([c], c.company_id == ^company_id and c.id == ^contract_id)
          |> Repo.one()

        cond do
          is_nil(contract) ->
            Errors.not_found(:contract)

          not ContractStatus.can_edit?(contract) ->
            Errors.business_rule(:contract_not_editable, %{
              contract_id: contract_id,
              status: contract.status
            })

          true ->
            RepoHelpers.transaction(fn ->
              contract
              |> Ecto.Changeset.change()
              |> Ecto.Changeset.put_assoc(:contract_items, [])
              |> Repo.update()

              contract
              |> Contract.update_changeset(attrs)
              |> RepoHelpers.update_or_abort()
              |> then(fn contract ->
                if Enum.empty?(items_attrs) do
                  {:ok, contract}
                else
                  create_contract_items(contract, items_attrs)
                end
              end)
            end)
        end
    end
  end

  def get_contract_for_user(%{id: user_id}, contract_id),
    do: get_contract_for_user(user_id, contract_id)

  def get_contract_for_user(user_id, contract_id) when is_binary(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        Errors.not_found(:company)

      %Company{id: company_id} ->
        Contract
        |> where([c], c.company_id == ^company_id and c.id == ^contract_id)
        |> Repo.one()
        |> case do
          nil ->
            Errors.not_found(:contract)

          contract ->
            {:ok,
             Repo.preload(contract, [
               :company,
               :buyer,
               :bank_account,
               :contract_items,
               bank_account: [:bank, :kbe_code, :knp_code]
             ])}
        end
    end
  end

  def issue_contract_for_user(user_id, contract_id) when is_binary(user_id) do
    RepoHelpers.transaction(fn ->
      case Companies.get_company_by_user_id(user_id) do
        nil ->
          RepoHelpers.abort({:not_found, %{resource: :company}})

        %Company{id: company_id} ->
          contract =
            RepoHelpers.fetch_or_abort(
              from(c in Contract, where: c.company_id == ^company_id and c.id == ^contract_id),
              :contract
            )

          if ContractStatus.already_issued?(contract) do
            RepoHelpers.abort(
              {:business_rule, %{rule: :contract_already_issued, contract_id: contract.id}}
            )
          end

          # Validate contract has required buyer details
          if is_nil(contract.buyer_id) and is_nil(contract.buyer_name) do
            RepoHelpers.abort(
              {:business_rule, %{rule: :buyer_required, contract_id: contract.id}}
            )
          end

          contract
          |> Ecto.Changeset.change(
            status: ContractStatus.issued(),
            issued_at: DateTime.utc_now() |> DateTime.truncate(:second)
          )
          |> RepoHelpers.update_or_abort()
      end
    end)
    |> Errors.normalize()
  end

  # Helper function to create contract items
  defp create_contract_items(contract, items_attrs) when is_list(items_attrs) do
    Enum.reduce_while(items_attrs, {:ok, contract}, fn item_attrs, {:ok, contract} ->
      alias EdocApi.Core.ContractItem

      %ContractItem{}
      |> ContractItem.changeset(item_attrs, contract.id)
      |> Repo.insert()
      |> case do
        {:ok, _item} -> {:cont, {:ok, contract}}
        {:error, changeset} -> {:halt, Errors.from_changeset({:error, changeset})}
      end
    end)
  end

  defp create_contract_items(contract, _), do: {:ok, contract}
end
