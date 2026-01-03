defmodule EdocApi.Core do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Core.Company
  alias EdocApi.Core.Invoice

  # ----- Companies--------
  def get_company_by_user_id(user_id) when is_binary(user_id) do
    Repo.get_by(Company, user_id: user_id)
  end

  # def upsert_company_for_user(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
  #   case get_company_by_user_id(user_id) do
  #     nil ->
  #       %Company{}
  #       |> Company.changeset(attrs, user_id)
  #       |> Repo.insert()

  #     %Company{} = company ->
  #       company
  #       |> Company.changeset(attrs, user_id)
  #       |> Repo.update()
  #   end
  # end

  def upsert_company_for_user(user_id, attrs) do
    company = get_company_by_user_id(user_id) || %Company{}

    changeset = Company.changeset(company, attrs, user_id)
    warnings = Company.warnings_from_changeset(changeset)

    case Repo.insert_or_update(changeset) do
      {:ok, company} ->
        {:ok, company, warnings}

      {:error, changeset} ->
        # тут будут настоящие ошибки (не warnings)
        {:error, changeset, Company.warnings_from_changeset(changeset)}
    end
  end

  # ----- Invoices--------
  # def get_invoice_for_user(user_id, invoice_id)
  #     when is_binary(user_id) and is_binary(invoice_id) do
  #   Repo.get_by(Invoice, id: invoice_id, user_id: user_id)
  # end

  def get_invoice_for_user(user_id, invoice_id)
      when is_binary(user_id) and is_binary(invoice_id) do
    Invoice
    |> where([i], i.id == ^invoice_id and i.user_id == ^user_id)
    |> preload([:company, :items])
    |> Repo.one()
  end

  def create_invoice_for_user(user_id, company_id, attrs)
      when is_binary(user_id) and is_binary(company_id) and is_map(attrs) do
    %Invoice{}
    |> Invoice.changeset(attrs, user_id, company_id)
    |> Repo.insert()
  end
end
