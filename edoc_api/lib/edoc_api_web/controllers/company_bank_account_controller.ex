defmodule EdocApiWeb.CompanyBankAccountController do
  use EdocApiWeb, :controller

  alias EdocApi.Core

  def index(conn, _params) do
    user = conn.assigns.current_user
    accounts = Core.list_company_bank_accounts_for_user(user.id)

    json(conn, %{bank_accounts: Enum.map(accounts, &bank_account_json/1)})
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    case Core.create_company_bank_account_for_user(user.id, params) do
      {:ok, acc} ->
        conn |> put_status(:created) |> json(%{bank_account: bank_account_json(acc)})

      {:error, :company_required} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "company_required"})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", details: errors_to_map(cs)})
    end
  end

  defp bank_account_json(a) do
    %{
      id: a.id,
      label: a.label,
      iban: a.iban,
      is_default: a.is_default,
      bank: a.bank && %{id: a.bank.id, name: a.bank.name, bic: a.bank.bic},
      kbe: a.kbe_code && %{id: a.kbe_code.id, code: a.kbe_code.code},
      knp: a.knp_code && %{id: a.knp_code.id, code: a.knp_code.code}
    }
  end

  # можно вынести в общий helper (у тебя он уже есть в InvoiceController)
  defp errors_to_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
