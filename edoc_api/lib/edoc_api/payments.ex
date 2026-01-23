defmodule EdocApi.Payments do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Companies
  alias EdocApi.Core.{Bank, CompanyBankAccount, KbeCode, KnpCode}

  def list_company_bank_accounts_for_user(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        []

      company ->
        CompanyBankAccount
        |> where([a], a.company_id == ^company.id)
        |> order_by([a], desc: a.is_default, asc: a.label)
        |> Repo.all()
        |> Repo.preload([:bank, :kbe_code, :knp_code])
    end
  end

  def create_company_bank_account_for_user(user_id, attrs) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        {:error, :company_required}

      company ->
        %CompanyBankAccount{}
        |> CompanyBankAccount.changeset(attrs, company.id)
        |> Repo.insert()
        |> case do
          {:ok, acc} -> {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}
          {:error, cs} -> {:error, cs}
        end
    end
  end

  def set_default_bank_account(user_id, bank_account_id) do
    Repo.transaction(fn ->
      with {:ok, company} <- get_company_or_rollback(user_id),
           {:ok, bank_account} <- verify_bank_account_ownership(company.id, bank_account_id) do
        # Only reset if this account is not already default
        if bank_account.is_default do
          bank_account
        else
          # Reset all defaults FIRST (before any validation that could fail)
          CompanyBankAccount.reset_all_defaults(company.id)

          # Now set the new default
          {:ok, acc} =
            bank_account
            |> CompanyBankAccount.set_as_default_changeset(%{}, company.id)
            |> Repo.update()

          acc
        end
      else
        {:error, reason} -> Repo.rollback(reason)
        nil -> Repo.rollback(:bank_account_not_found)
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_company_or_rollback(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil -> {:error, :company_required}
      company -> {:ok, company}
    end
  end

  defp verify_bank_account_ownership(company_id, bank_account_id) do
    case Repo.get(CompanyBankAccount, bank_account_id) do
      %CompanyBankAccount{company_id: ^company_id} = acc -> {:ok, acc}
      _ -> {:error, :bank_account_not_found}
    end
  end

  @doc false
  def set_default_bank_account_for_company!(company_id, bank_account_id) do
    # Transaction-safe pattern for internal use
    {:ok, acc} =
      Repo.transaction(fn ->
        bank_account =
          CompanyBankAccount
          |> where([a], a.id == ^bank_account_id and a.company_id == ^company_id)
          |> Repo.one!()

        # Only reset if this account is not already default
        if bank_account.is_default do
          bank_account
        else
          CompanyBankAccount.reset_all_defaults(company_id)

          bank_account
          |> CompanyBankAccount.set_as_default_changeset(%{}, company_id)
          |> Repo.update!()
        end
      end)

    # Reload from database to ensure we have the latest state
    Repo.get(CompanyBankAccount, acc.id)
  end

  def list_banks do
    Bank |> order_by([b], asc: b.name) |> Repo.all()
  end

  def list_kbe_codes do
    KbeCode |> order_by([k], asc: k.code) |> Repo.all()
  end

  def list_knp_codes do
    KnpCode |> order_by([k], asc: k.code) |> Repo.all()
  end
end
