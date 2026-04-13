defmodule EdocApiWeb.InvoiceController do
  use EdocApiWeb, :controller

  alias EdocApi.Companies
  alias EdocApiWeb.{ErrorMapper, ControllerHelpers}
  alias EdocApi.Invoicing
  alias EdocApi.Documents.PdfRequests
  alias EdocApiWeb.Serializers.InvoiceSerializer

  def create(conn, params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        ErrorMapper.unprocessable(conn, "company_required")

      company ->
        result = Invoicing.create_invoice_for_user(user.id, company.id, params)

        ControllerHelpers.handle_common_result(conn, result, fn conn, invoice ->
          conn
          |> put_status(:created)
          |> json(%{invoice: InvoiceSerializer.to_map(invoice)})
        end)
    end
  end

  def index(conn, params) do
    user = conn.assigns.current_user

    %{page: page, page_size: page_size, offset: offset} =
      ControllerHelpers.pagination_params(params)

    invoices =
      Invoicing.list_invoices_for_user(user.id, limit: page_size, offset: offset)

    total_count = Invoicing.count_invoices_for_user(user.id)

    json(conn, %{
      invoices: Enum.map(invoices, &InvoiceSerializer.to_map/1),
      meta: ControllerHelpers.pagination_meta(page, page_size, total_count)
    })
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        ErrorMapper.not_found(conn, "invoice_not_found")

      invoice ->
        json(conn, %{invoice: InvoiceSerializer.to_map(invoice)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    result = Invoicing.update_invoice_for_user(user.id, id, params)

    ControllerHelpers.handle_common_result(conn, result, fn conn, invoice ->
      json(conn, %{invoice: InvoiceSerializer.to_map(invoice)})
    end)
  end

  def issue(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    result = Invoicing.issue_invoice_for_user(user.id, id)

    ControllerHelpers.handle_common_result(
      conn,
      result,
      fn conn, invoice ->
        json(conn, %{invoice: InvoiceSerializer.to_map(invoice)})
      end,
      %{
        business_rule: &handle_issue_business_rule/2
      }
    )
  end

  def pay(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    result = Invoicing.pay_invoice_for_user(user.id, id)

    ControllerHelpers.handle_common_result(
      conn,
      result,
      fn conn, invoice ->
        json(conn, %{invoice: InvoiceSerializer.to_map(invoice)})
      end,
      %{
        cannot_mark_paid: fn conn, details ->
          ErrorMapper.unprocessable(conn, "cannot_mark_paid", details)
        end,
        already_paid: fn conn, details ->
          ErrorMapper.unprocessable(conn, "already_paid", details)
        end,
        contract_must_be_signed_to_pay_invoice: fn conn, details ->
          ErrorMapper.unprocessable(conn, "contract_must_be_signed_to_pay_invoice", details)
        end
      }
    )
  end

  def pdf(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    conn = put_layout(conn, false)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        ErrorMapper.not_found(conn, "invoice_not_found")

      invoice ->
        # Pre-render HTML in web layer, then pass to PDF module
        html = EdocApiWeb.PdfTemplates.invoice_html(invoice)

        case PdfRequests.fetch_or_enqueue(:invoice, invoice.id, user.id, html) do
          {:ok, pdf_binary} ->
            conn
            |> put_pdf_security_headers()
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="invoice-#{invoice.number}.pdf")
            )
            |> send_resp(200, pdf_binary)

          {:pending, _} ->
            conn
            |> put_status(:accepted)
            |> json(%{status: "pending", poll_url: "/v1/invoices/#{invoice.id}/pdf/status"})

          {:error, _reason} ->
            ErrorMapper.unprocessable(conn, "pdf_generation_failed")
        end
    end
  end

  def pdf_status(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        ErrorMapper.not_found(conn, "invoice_not_found")

      invoice ->
        case PdfRequests.status(:invoice, invoice.id, user.id) do
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

  defp handle_issue_business_rule(
         conn,
         %{details: %{rule: :contract_must_be_signed_to_issue_invoice} = details}
       ) do
    ErrorMapper.unprocessable(conn, "contract_must_be_signed_to_issue_invoice", details)
  end

  defp handle_issue_business_rule(conn, %{rule: :quota_exceeded} = details) do
    ErrorMapper.unprocessable(conn, "quota_exceeded", details)
  end

  defp handle_issue_business_rule(conn, %{details: %{rule: :quota_exceeded} = details}) do
    ErrorMapper.unprocessable(conn, "quota_exceeded", details)
  end

  defp handle_issue_business_rule(conn, details) do
    ErrorMapper.unprocessable(conn, "business_rule", details)
  end
end
