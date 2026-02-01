defmodule EdocApiWeb.InvoicesController do
  use EdocApiWeb, :controller

  alias EdocApi.Invoicing
  alias EdocApi.Documents.InvoicePdf
  alias EdocApiWeb.UnifiedErrorHandler

  # Get current user from conn.assigns (set by auth plug)
  defp current_user(conn), do: conn.assigns.current_user

  def index(conn, _params) do
    user = current_user(conn)
    invoices = Invoicing.list_invoices_for_user(user.id)

    # Render the HTML template
    render(conn, :index, invoices: invoices, page_title: "Invoices")
  end

  def show(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Invoice not found")
        |> redirect(to: "/invoices")

      invoice ->
        render(conn, :show, invoice: invoice, page_title: "Invoice #{invoice.number}")
    end
  end

  def new(conn, _params) do
    # Render new invoice form
    # For POC, we'll just show a simple form
    render(conn, :new, page_title: "New Invoice")
  end

  def create(conn, %{"invoice" => invoice_params, "items" => items_params}) do
    user = current_user(conn)

    # Get company for user
    case EdocApi.Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company")

      company ->
        # Combine invoice params with items
        invoice_params_with_items =
          invoice_params
          |> Map.put("items", Map.values(items_params))

        case Invoicing.create_invoice_for_user(user.id, company.id, invoice_params_with_items) do
          {:ok, invoice} ->
            conn
            |> put_flash(:info, "Invoice created successfully")
            |> redirect(to: "/invoices/#{invoice.id}")

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_flash(
              :error,
              "Failed to create invoice: #{format_changeset_errors(changeset)}"
            )
            |> render(:new, page_title: "New Invoice")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Failed to create invoice: #{reason}")
            |> render(:new, page_title: "New Invoice")
        end
    end
  end

  def create(conn, %{"invoice" => _invoice_params}) do
    conn
    |> put_flash(:error, "At least one item is required")
    |> render(:new, page_title: "New Invoice")
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  def pdf(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Invoice not found")
        |> redirect(to: "/invoices")

      invoice ->
        case InvoicePdf.render(invoice) do
          {:ok, pdf_binary} ->
            conn
            |> put_layout(false)
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="invoice-#{invoice.number}.pdf")
            )
            |> send_resp(200, pdf_binary)

          {:error, _reason} ->
            conn
            |> put_status(:internal_server_error)
            |> put_flash(:error, "Failed to generate PDF")
            |> redirect(to: "/invoices/#{id}")
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = current_user(conn)
    result = Invoicing.delete_invoice_for_user(user.id, id)

    UnifiedErrorHandler.handle_result(conn, result,
      success: fn conn, _data ->
        if UnifiedErrorHandler.htmx_request?(conn) do
          send_resp(conn, :no_content, "")
        else
          conn
          |> put_flash(:info, "Invoice deleted successfully")
          |> redirect(to: "/invoices")
        end
      end,
      error: fn conn, type, details ->
        cond do
          type == :business_rule && details[:rule] == :cannot_delete_issued_invoice ->
            if UnifiedErrorHandler.htmx_request?(conn) do
              conn
              |> put_resp_content_type("text/html")
              |> send_resp(403, "<span class='text-red-600'>Cannot delete issued invoice</span>")
            else
              conn
              |> put_flash(:error, "Cannot delete issued invoice")
              |> redirect(to: "/invoices")
            end

          true ->
            if UnifiedErrorHandler.htmx_request?(conn) do
              conn
              |> put_resp_content_type("text/html")
              |> send_resp(404, "<span class='text-red-600'>Error deleting invoice</span>")
            else
              conn
              |> put_flash(:error, "Error deleting invoice")
              |> redirect(to: "/invoices")
            end
        end
      end
    )
  end
end
