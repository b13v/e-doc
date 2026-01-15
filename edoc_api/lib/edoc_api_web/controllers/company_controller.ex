defmodule EdocApiWeb.CompanyController do
  use EdocApiWeb, :controller

  alias EdocApi.Companies
  alias EdocApiWeb.Serializers.CompanySerializer
  alias EdocApiWeb.Serializers.ErrorSerializer

  def show(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "company_not_found"})

      company ->
        json(conn, %{company: CompanySerializer.to_map(company)})
    end
  end

  def upsert(conn, params) do
    user = conn.assigns.current_user

    # case Core.upsert_company_for_user(user.id, params) do
    #   {:ok, company} ->
    #     json(conn, %{company: company_json(company)})

    #   {:error, %Ecto.Changeset{} = changeset} ->
    #     conn
    #     |> put_status(:unprocessable_entity)
    #     |> json(%{error: "validation_error", details: errors_to_map(changeset)})
    # end
    case Companies.upsert_company_for_user(user.id, params) do
      {:ok, company, warnings} ->
        json(conn, %{company: CompanySerializer.to_map(company), warnings: warnings})

      {:error, %Ecto.Changeset{} = changeset, warnings} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "validation_error",
          details: ErrorSerializer.errors_to_map(changeset),
          warnings: warnings
        })
    end
  end
end
