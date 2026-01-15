defmodule EdocApi.Companies do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Core.Company

  def get_company_by_user_id(user_id) when is_binary(user_id) do
    Repo.get_by(Company, user_id: user_id)
  end

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
end
