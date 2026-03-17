defmodule EdocApiWeb.CompanyBankAccountHTMLController do
  use EdocApiWeb, :controller
  plug(:put_view, html: EdocApiWeb.CompanyBankAccountHTML)

  alias EdocApi.Companies
  alias EdocApi.Payments

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, _company} <- require_company(user.id),
         {:ok, account} <- Payments.get_company_bank_account_for_user(user.id, id) do
      render(conn, :show, account: account, page_title: "Bank Account")
    else
      {:error, :company_required} ->
        conn
        |> put_flash(:error, "Пожалуйста, сначала зарегистрируйте свою компанию.")
        |> redirect(to: "/company/setup")

      {:error, :bank_account_not_found} ->
        conn
        |> put_flash(:error, "Банковский счет не найден.")
        |> redirect(to: "/company")
    end
  end

  def edit(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, _company} <- require_company(user.id),
         {:ok, account} <- Payments.get_company_bank_account_for_user(user.id, id) do
      render(conn, :edit, account: account, page_title: "Edit Bank Account")
    else
      {:error, :company_required} ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company/setup")

      {:error, :bank_account_not_found} ->
        conn
        |> put_flash(:error, "Bank account not found")
        |> redirect(to: "/company")
    end
  end

  def update(conn, %{"id" => id, "bank_account" => bank_account_params}) do
    user = conn.assigns.current_user

    attrs =
      bank_account_params
      |> Map.take(["label", "bank_id", "iban"])

    with {:ok, _company} <- require_company(user.id),
         {:ok, _account} <- Payments.update_company_bank_account_for_user(user.id, id, attrs) do
      conn
      |> put_flash(:info, "Bank account updated successfully")
      |> redirect(to: "/company")
    else
      {:error, :company_required} ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company/setup")

      {:error, :bank_account_not_found} ->
        conn
        |> put_flash(:error, "Bank account not found")
        |> redirect(to: "/company")

      {:error, %Ecto.Changeset{} = changeset} ->
        case Payments.get_company_bank_account_for_user(user.id, id) do
          {:ok, account} ->
            conn
            |> put_flash(:error, format_changeset_errors(changeset))
            |> render(:edit,
              account: account,
              changeset: changeset,
              page_title: "Edit Bank Account"
            )

          {:error, _reason} ->
            conn
            |> put_flash(:error, "Bank account not found")
            |> redirect(to: "/company")
        end
    end
  end

  defp require_company(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil -> {:error, :company_required}
      company -> {:ok, company}
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end
end
