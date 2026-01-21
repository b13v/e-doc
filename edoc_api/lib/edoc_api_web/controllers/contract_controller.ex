defmodule EdocApiWeb.ContractController do
  use EdocApiWeb, :controller

  alias EdocApi.Core
  alias EdocApiWeb.{ErrorMapper, ControllerHelpers}

  def index(conn, _params) do
    user = conn.assigns.current_user
    contracts = Core.list_contracts_for_user(user)

    render(conn, :index, contracts: contracts)
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    attrs = Map.get(params, "contract", params)

    result = Core.create_contract_for_user(user, attrs)

    ControllerHelpers.handle_common_result(conn, result, fn conn, contract ->
      conn
      |> put_status(:created)
      |> render(:show, contract: contract)
    end)
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    result = Core.get_contract_for_user(user, id)

    error_map = %{
      not_found: &ErrorMapper.not_found(&1, "contract_not_found")
    }

    ControllerHelpers.handle_result(
      conn,
      result,
      fn conn, contract ->
        render(conn, :show, contract: contract)
      end,
      error_map
    )
  end
end
