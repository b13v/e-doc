defmodule EdocApiWeb.CompanyController do
  use EdocApiWeb, :controller

  alias EdocApi.Companies

  def show(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "company_not_found"})

      company ->
        json(conn, %{company: company_json(company)})
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
        json(conn, %{company: company_json(company), warnings: warnings})

      {:error, %Ecto.Changeset{} = changeset, warnings} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "validation_error",
          details: errors_to_map(changeset),
          warnings: warnings
        })
    end
  end

  defp company_json(company) do
    %{
      id: company.id,
      name: company.name,
      legal_form: company.legal_form,
      bin_iin: company.bin_iin,
      city: company.city,
      address: company.address,
      bank: company.bank,
      iban: company.iban,
      email: company.email,
      phone: company.phone,
      representative_name: company.representative_name,
      representative_title: company.representative_title,
      basis: company.basis,
      inserted_at: company.inserted_at,
      updated_at: company.updated_at
    }
  end

  defp errors_to_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
