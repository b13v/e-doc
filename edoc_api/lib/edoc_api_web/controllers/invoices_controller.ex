defmodule EdocApiWeb.InvoicesController do
  use EdocApiWeb, :controller

  alias EdocApi.Invoicing
  alias EdocApi.InvoiceStatus
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
          |> Map.put("items", items_params)

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

          {:error, :validation, %{changeset: changeset}} ->
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

  def edit(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Invoice not found")
        |> redirect(to: "/invoices")

      invoice ->
        if InvoiceStatus.is_draft?(invoice.status) do
          changeset = Ecto.Changeset.change(invoice)

          render(conn, :edit,
            invoice: invoice,
            changeset: changeset,
            page_title: "Edit Invoice #{invoice.number}"
          )
        else
          conn
          |> put_flash(:error, "Only draft invoices can be edited")
          |> redirect(to: "/invoices/#{id}")
        end
    end
  end

  def update(conn, %{"id" => id, "invoice" => invoice_params}) do
    user = current_user(conn)

    case Invoicing.update_invoice_for_user(user.id, id, invoice_params) do
      {:ok, invoice} ->
        conn
        |> put_flash(:info, "Invoice updated successfully")
        |> redirect(to: "/invoices/#{invoice.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        invoice = Invoicing.get_invoice_for_user(user.id, id)

        conn
        |> put_flash(:error, "Failed to update invoice: #{format_changeset_errors(changeset)}")
        |> render(:edit,
          invoice: invoice,
          changeset: changeset,
          page_title: "Edit Invoice #{invoice.number}"
        )

      {:error, reason} ->
        invoice = Invoicing.get_invoice_for_user(user.id, id)

        conn
        |> put_flash(:error, "Failed to update invoice: #{reason}")
        |> render(:edit,
          invoice: invoice,
          changeset: Ecto.Changeset.change(invoice, invoice_params),
          page_title: "Edit Invoice #{invoice.number}"
        )
    end
  end

  def issue(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.issue_invoice_for_user(user.id, id) do
      {:ok, invoice} ->
        conn
        |> put_flash(:info, "Invoice issued successfully")
        |> redirect(to: "/invoices/#{invoice.id}")

      {:error, {:business_rule, %{rule: :cannot_issue}}} ->
        conn
        |> put_flash(:error, "Only draft invoices can be issued")
        |> redirect(to: "/invoices/#{id}")

      {:error, {:business_rule, %{rule: :already_issued}}} ->
        conn
        |> put_flash(:error, "Invoice is already issued")
        |> redirect(to: "/invoices/#{id}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to issue invoice: #{inspect(reason)}")
        |> redirect(to: "/invoices/#{id}")
    end
  end
end
