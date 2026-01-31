defmodule EdocApiWeb.ContractController do
  use EdocApiWeb, :controller

  alias EdocApi.Core
  alias EdocApi.Documents.ContractPdf
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

    error_map = %{
      company_required: &ErrorMapper.bad_request(&1, "company_required"),
      buyer_required: &ErrorMapper.unprocessable(&1, "buyer_required")
    }

    ControllerHelpers.handle_common_result(
      conn,
      result,
      fn conn, contract ->
        conn
        |> put_status(:created)
        |> render(:show, contract: contract)
      end,
      error_map
    )
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

  def issue(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    result = Core.issue_contract_for_user(user.id, id)

    error_map = %{
      not_found: &ErrorMapper.not_found(&1, "contract_not_found"),
      contract_already_issued: &ErrorMapper.unprocessable(&1, "contract_already_issued"),
      buyer_required: &ErrorMapper.unprocessable(&1, "buyer_required")
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

  def pdf(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    conn = put_layout(conn, false)

    case Core.get_contract_for_user(user, id) do
      {:error, :not_found} ->
        ErrorMapper.not_found(conn, "contract_not_found")

      {:ok, contract} ->
        result = ContractPdf.render(contract)

        error_map = %{
          pdf_generation_failed: fn conn, details ->
            ErrorMapper.unprocessable(conn, "pdf_generation_failed", details)
          end
        }

        ControllerHelpers.handle_result(
          conn,
          result,
          fn conn, pdf_binary ->
            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="contract-#{contract.number}.pdf")
            )
            |> send_resp(200, pdf_binary)
          end,
          error_map
        )
    end
  end
end
