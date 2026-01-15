defmodule EdocApiWeb.InvoiceController do
  use EdocApiWeb, :controller

  alias EdocApi.Companies
  alias EdocApi.Invoicing
  alias EdocApiWeb.PdfTemplates
  alias EdocApiWeb.Serializers.ErrorSerializer
  alias EdocApiWeb.Serializers.InvoiceSerializer
  require Logger

  def create(conn, params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "company_required"})

      company ->
        case Invoicing.create_invoice_for_user(user.id, company.id, params) do
          {:ok, invoice} ->
            conn
            |> put_status(:created)
            |> json(%{invoice: InvoiceSerializer.to_map(invoice)})

          {:error, :items_required} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "items_required"})

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "validation_error",
              details: ErrorSerializer.errors_to_map(changeset)
            })

          {:error, other} ->
            Logger.error("invoice_create_failed: #{inspect(other)}")

            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "internal_error"})
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
        conn |> put_status(:not_found) |> json(%{error: "invoice_not_found"})

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
        conn |> put_status(:not_found) |> json(%{error: "invoice_not_found"})

      {:error, :already_issued} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "already_issued"})

      {:error, :cannot_issue, details} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "cannot_issue", details: details})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", details: ErrorSerializer.errors_to_map(cs)})
    end
  end

  def pdf(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    conn = put_layout(conn, false)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "invoice_not_found"})

      invoice ->
        html = PdfTemplates.invoice_html(invoice)

        case EdocApi.Pdf.html_to_pdf(html) do
          {:ok, pdf_binary} ->
            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="invoice-#{invoice.number}.pdf")
            )
            |> send_resp(200, pdf_binary)

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "pdf_generation_failed", reason: inspect(reason)})
        end
    end
  end
end
