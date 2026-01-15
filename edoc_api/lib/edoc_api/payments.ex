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
