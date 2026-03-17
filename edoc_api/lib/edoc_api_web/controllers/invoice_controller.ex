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

    ControllerHelpers.handle_common_result(conn, result, fn conn, invoice ->
      json(conn, %{invoice: InvoiceSerializer.to_map(invoice)})
    end)
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
        result = InvoicePdf.render(invoice)

        error_map = %{
          pdf_generation_failed: fn conn ->
            ErrorMapper.unprocessable(conn, "pdf_generation_failed")
          end
        }

        ControllerHelpers.handle_result(
          conn,
          result,
          fn conn, pdf_binary ->
            conn
            |> put_pdf_security_headers()
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

  defp put_pdf_security_headers(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store, max-age=0")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("x-content-type-options", "nosniff")
  end
end
