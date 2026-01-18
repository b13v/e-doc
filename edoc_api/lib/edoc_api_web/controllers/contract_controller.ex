defmodule EdocApiWeb.ContractController do
  use EdocApiWeb, :controller

  alias EdocApi.Core
  alias EdocApiWeb.ErrorMapper

  def index(conn, _params) do
    user = conn.assigns.current_user
    contracts = Core.list_contracts_for_user(user)

    render(conn, :index, contracts: contracts)
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    attrs = Map.get(params, "contract", params)

    case Core.create_contract_for_user(user, attrs) do
      {:ok, contract} ->
        conn
        |> put_status(:created)
        |> render(:show, contract: contract)

      {:error, :company_required} ->
        ErrorMapper.unprocessable(conn, "company_required")

      {:error, %Ecto.Changeset{} = changeset} ->
        ErrorMapper.validation(conn, changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.get_contract_for_user(user, id) do
      {:ok, contract} ->
        render(conn, :show, contract: contract)

      {:error, :not_found} ->
        ErrorMapper.not_found(conn, "contract_not_found")
    end
  end
end
