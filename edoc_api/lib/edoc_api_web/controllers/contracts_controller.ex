defmodule EdocApiWeb.ContractsController do
  use EdocApiWeb, :controller

  alias EdocApi.Core

  def index(conn, _params) do
    user = conn.assigns.current_user
    contracts = Core.list_contracts_for_user(user.id)
    render(conn, :index, contracts: contracts, page_title: "Contracts")
  end
end
