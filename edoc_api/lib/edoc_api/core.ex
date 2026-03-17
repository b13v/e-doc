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
  alias EdocApi.Core.ContractItem
  alias EdocApi.Core.UnitOfMeasurement
  alias EdocApi.ContractStatus

  defdelegate get_company_by_user_id(user_id), to: Companies
  defdelegate upsert_company_for_user(user_id, attrs), to: Companies

  defdelegate list_company_bank_accounts_for_user(user_id), to: Payments
  defdelegate create_company_bank_account_for_user(user_id, attrs), to: Payments
  defdelegate list_banks(), to: Payments
  defdelegate list_kbe_codes(), to: Payments
  defdelegate list_knp_codes(), to: Payments

  def list_units_of_measurements do
    UnitOfMeasurement
    |> order_by([u], asc: u.symbol, asc: u.name)
    |> Repo.all()
  end

  defdelegate get_invoice_for_user(user_id, invoice_id), to: Invoicing
  defdelegate list_invoices_for_user(user_id, opts \\ []), to: Invoicing
  defdelegate issue_invoice_for_user(user_id, invoice_id), to: Invoicing
  defdelegate create_invoice_for_user(user_id, company_id, attrs), to: Invoicing
  defdelegate next_invoice_number!(company_id), to: Invoicing
  defdelegate mark_invoice_issued(invoice), to: Invoicing

  def list_contracts_for_user(user_id_or_struct, opts \\ [])

  def list_contracts_for_user(%{id: user_id}, opts),
    do: list_contracts_for_user(user_id, opts)

  def list_contracts_for_user(user_id, opts) when is_binary(user_id) do
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
        |> apply_pagination(opts)
        |> Repo.all()
    end
  end

  def count_contracts_for_user(%{id: user_id}), do: count_contracts_for_user(user_id)

  def count_contracts_for_user(user_id) when is_binary(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        0

      %Company{id: company_id} ->
        Contract
        |> where([c], c.company_id == ^company_id)
        |> Repo.aggregate(:count, :id)
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
          with {:ok, contract} <-
                 %Contract{}
                 |> Contract.changeset(attrs, company_id)
                 |> RepoHelpers.insert_or_abort(),
               {:ok, _} <-
                 if(Enum.empty?(items_attrs),
                   do: {:ok, nil},
                   else: create_contract_items(contract, items_attrs)
                 ) do
            reloaded_contract = Repo.get(Contract, contract.id) |> Repo.preload(:contract_items)
            {:ok, reloaded_contract}
          end
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
          |> Repo.preload(:contract_items)

        cond do
          is_nil(contract) ->
            Errors.not_found(:contract)

          not ContractStatus.can_edit?(contract) ->
            Errors.business_rule(:contract_not_editable, %{
              contract_id: contract_id,
              status: contract.status
            })

          true ->
            contract
            |> update_contract_with_items(attrs, items_attrs)
            |> Errors.normalize()
        end
    end
  end

  defp apply_pagination(query, opts) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset)

    query =
      if is_integer(limit) do
        from(q in query, limit: ^limit)
      else
        query
      end

    if is_integer(offset) and offset > 0 do
      from(q in query, offset: ^offset)
    else
      query
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
               :bank_account,
               :contract_items,
               buyer: [bank_accounts: :bank],
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

  def delete_contract_for_user(user_id, contract_id) when is_binary(user_id) do
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
            case Repo.delete(contract) do
              {:ok, deleted_contract} -> {:ok, deleted_contract}
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end

  # Helper function to create contract items
  defp create_contract_items(contract, items_attrs) when is_list(items_attrs) do
    require Logger
    Logger.info("Creating #{length(items_attrs)} contract items for contract #{contract.id}")

    Enum.reduce_while(items_attrs, {:ok, contract}, fn item_attrs, {:ok, contract} ->
      alias EdocApi.Core.ContractItem

      %ContractItem{}
      |> ContractItem.changeset(item_attrs, contract.id)
      |> Repo.insert()
      |> case do
        {:ok, item} ->
          Logger.info("Created contract item: #{item.name}")
          {:cont, {:ok, contract}}

        {:error, changeset} ->
          Logger.error("Failed to create contract item: #{inspect(changeset.errors)}")
          {:halt, RepoHelpers.abort({:validation, %{changeset: changeset}})}
      end
    end)
  end

  defp create_contract_items(contract, _), do: {:ok, contract}

  defp update_contract_with_items(contract, attrs, items_attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:contract, Contract.update_changeset(contract, attrs || %{}))
    |> Ecto.Multi.delete_all(:delete_contract_items, contract_items_query(contract.id))
    |> Ecto.Multi.run(:insert_contract_items, fn repo, _changes ->
      insert_contract_items(repo, contract.id, items_attrs)
    end)
    |> Ecto.Multi.run(:reloaded_contract, fn repo, %{contract: updated_contract} ->
      {:ok, repo.get(Contract, updated_contract.id) |> repo.preload(:contract_items)}
    end)
    |> Repo.transaction()
    |> normalize_contract_update_result()
  end

  defp insert_contract_items(_repo, _contract_id, items_attrs) when items_attrs == [],
    do: {:ok, :ok}

  defp insert_contract_items(repo, contract_id, items_attrs) when is_list(items_attrs) do
    Enum.reduce_while(items_attrs, {:ok, :ok}, fn item_attrs, {:ok, :ok} ->
      %ContractItem{}
      |> ContractItem.changeset(item_attrs, contract_id)
      |> repo.insert()
      |> case do
        {:ok, _item} -> {:cont, {:ok, :ok}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp contract_items_query(contract_id) do
    from(ci in ContractItem, where: ci.contract_id == ^contract_id)
  end

  defp normalize_contract_update_result({:ok, %{reloaded_contract: contract}}),
    do: {:ok, contract}

  defp normalize_contract_update_result(
         {:error, _step, %Ecto.Changeset{} = changeset, _changes_so_far}
       ) do
    {:error, :validation, %{changeset: changeset}}
  end

  defp normalize_contract_update_result({:error, _step, reason, _changes_so_far}) do
    {:error, reason}
  end
end
