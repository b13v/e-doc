defmodule EdocApiWeb.InvoiceController do
  use EdocApiWeb, :controller

  alias EdocApi.Companies
  alias EdocApiWeb.ErrorMapper
  alias EdocApi.Invoicing
  alias EdocApi.Documents.InvoicePdf
  alias EdocApiWeb.Serializers.InvoiceSerializer
  require Logger

  def create(conn, params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        ErrorMapper.unprocessable(conn, "company_required")

      company ->
        case Invoicing.create_invoice_for_user(user.id, company.id, params) do
          {:ok, invoice} ->
            conn
            |> put_status(:created)
            |> json(%{invoice: InvoiceSerializer.to_map(invoice)})

          {:error, :items_required} ->
            ErrorMapper.unprocessable(conn, "items_required")

          {:error, %Ecto.Changeset{} = changeset} ->
            ErrorMapper.validation(conn, changeset)

          {:error, other} ->
            Logger.error("invoice_create_failed: #{inspect(other)}")
            ErrorMapper.internal(conn)
        end
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

  def issue(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Invoicing.issue_invoice_for_user(user.id, id) do
      {:ok, invoice} ->
        json(conn, %{invoice: InvoiceSerializer.to_map(invoice)})

      {:error, :invoice_not_found} ->
        ErrorMapper.not_found(conn, "invoice_not_found")

      {:error, :already_issued} ->
        ErrorMapper.unprocessable(conn, "already_issued")

      {:error, :cannot_issue, details} ->
        ErrorMapper.unprocessable(conn, "cannot_issue", details)

      {:error, %Ecto.Changeset{} = cs} ->
        ErrorMapper.validation(conn, cs)
    end
  end

  def pdf(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    conn = put_layout(conn, false)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        ErrorMapper.not_found(conn, "invoice_not_found")

      invoice ->
        case InvoicePdf.render(invoice) do
          {:ok, pdf_binary} ->
            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="invoice-#{invoice.number}.pdf")
            )
            |> send_resp(200, pdf_binary)

          {:error, reason} ->
            ErrorMapper.unprocessable(conn, "pdf_generation_failed", %{reason: inspect(reason)})
        end
    end
  end
end
