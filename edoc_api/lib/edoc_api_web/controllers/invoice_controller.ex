defmodule EdocApiWeb.InvoiceController do
  use EdocApiWeb, :controller

  alias EdocApi.Companies
  alias EdocApiWeb.{ErrorMapper, ControllerHelpers}
  alias EdocApi.Invoicing
  alias EdocApi.Documents.InvoicePdf
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

  def index(conn, _params) do
    user = conn.assigns.current_user
    invoices = Invoicing.list_invoices_for_user(user.id)

    json(conn, %{invoices: Enum.map(invoices, &InvoiceSerializer.to_map/1)})
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

    ControllerHelpers.handle_common_result(conn, result, fn conn, invoice ->
      json(conn, %{invoice: InvoiceSerializer.to_map(invoice)})
    end)
  end

  def pdf(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    conn = put_layout(conn, false)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        ErrorMapper.not_found(conn, "invoice_not_found")

      invoice ->
        result = InvoicePdf.render(invoice)

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
              ~s(inline; filename="invoice-#{invoice.number}.pdf")
            )
            |> send_resp(200, pdf_binary)
          end,
          error_map
        )
    end
  end
end
