defmodule EdocApiWeb.CompanyBankAccountController do
  use EdocApiWeb, :controller

  alias EdocApi.Payments
  alias EdocApiWeb.Serializers.BankAccountSerializer
  alias EdocApiWeb.Serializers.ErrorSerializer

  def index(conn, _params) do
    user = conn.assigns.current_user
    accounts = Payments.list_company_bank_accounts_for_user(user.id)

    json(conn, %{bank_accounts: Enum.map(accounts, &BankAccountSerializer.to_map/1)})
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    case Payments.create_company_bank_account_for_user(user.id, params) do
      {:ok, acc} ->
        conn |> put_status(:created) |> json(%{bank_account: BankAccountSerializer.to_map(acc)})

      {:error, :company_required} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "company_required"})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", details: ErrorSerializer.errors_to_map(cs)})
    end
  end
end
