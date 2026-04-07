defmodule EdocApi.Companies do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Core.Company
  alias EdocApi.Core.TenantMembership
  alias EdocApi.Monetization

  def get_company_by_user_id(user_id) when is_binary(user_id) do
    case Repo.get_by(Company, user_id: user_id) do
      %Company{} = company ->
        _ = Monetization.ensure_owner_membership(company.id, user_id)
        company

      nil ->
      (TenantMembership
       |> where([m], m.user_id == ^user_id and m.status == "active")
       |> order_by([m], asc: m.inserted_at)
       |> join(:inner, [m], c in Company, on: c.id == m.company_id)
       |> select([_m, c], c)
       |> limit(1)
       |> Repo.one())
    end
  end

  def upsert_company_for_user(user_id, attrs) do
    company = get_company_by_user_id(user_id) || %Company{}

    changeset = Company.changeset(company, attrs, user_id)
    warnings = Company.warnings_from_changeset(changeset)

    case Repo.insert_or_update(changeset) do
      {:ok, company} ->
        _ = Monetization.ensure_owner_membership(company.id, user_id)
        {:ok, company, warnings}

      {:error, changeset} ->
        # тут будут настоящие ошибки (не warnings)
        {:error, changeset, Company.warnings_from_changeset(changeset)}
    end
  end
end
