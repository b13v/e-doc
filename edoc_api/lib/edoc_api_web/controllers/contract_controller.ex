defmodule EdocApiWeb.ContractController do
  use EdocApiWeb, :controller

  alias EdocApi.Core
  alias EdocApi.Documents.PdfRequests
  alias EdocApiWeb.{ErrorMapper, ControllerHelpers}

  def index(conn, params) do
    user = conn.assigns.current_user

    %{page: page, page_size: page_size, offset: offset} =
      ControllerHelpers.pagination_params(params)

    contracts = Core.list_contracts_for_user(user, limit: page_size, offset: offset)
    total_count = Core.count_contracts_for_user(user)

    render(conn, :index,
      contracts: contracts,
      meta: ControllerHelpers.pagination_meta(page, page_size, total_count)
    )
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
      buyer_required: &ErrorMapper.unprocessable(&1, "buyer_required"),
      quota_exceeded: &ErrorMapper.unprocessable(&1, "quota_exceeded")
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

  def sign(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    result = Core.sign_contract_for_user(user.id, id)

    error_map = %{
      not_found: &ErrorMapper.not_found(&1, "contract_not_found"),
      contract_not_issued: &ErrorMapper.unprocessable(&1, "contract_not_issued"),
      contract_already_signed: &ErrorMapper.unprocessable(&1, "contract_already_signed")
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
      {:error, :not_found, _details} ->
        ErrorMapper.not_found(conn, "contract_not_found")

      {:ok, contract} ->
        # Pre-render HTML in web layer, then pass to PDF module
        html = EdocApiWeb.PdfTemplates.contract_html(contract)

        case PdfRequests.fetch_or_enqueue(:contract, contract.id, user.id, html) do
          {:ok, pdf_binary} ->
            conn
            |> put_pdf_security_headers()
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="contract-#{contract.number}.pdf")
            )
            |> send_resp(200, pdf_binary)

          {:pending, _} ->
            conn
            |> put_status(:accepted)
            |> json(%{status: "pending", poll_url: "/v1/contracts/#{contract.id}/pdf/status"})

          {:error, _reason} ->
            ErrorMapper.unprocessable(conn, "pdf_generation_failed")
        end
    end
  end

  def pdf_status(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.get_contract_for_user(user, id) do
      {:error, :not_found, _details} ->
        ErrorMapper.not_found(conn, "contract_not_found")

      {:ok, contract} ->
        case PdfRequests.status(:contract, contract.id, user.id) do
          {:ok, :completed} ->
            json(conn, %{status: "ready"})

          {:ok, status} when status in [:pending, :processing] ->
            conn |> put_status(:accepted) |> json(%{status: "pending"})

          {:ok, :failed} ->
            ErrorMapper.unprocessable(conn, "pdf_generation_failed")

          {:error, :not_found} ->
            ErrorMapper.not_found(conn, "pdf_not_found")
        end
    end
  end

  defp put_pdf_security_headers(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store, max-age=0")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("x-content-type-options", "nosniff")
  end
end
