defmodule EdocApiWeb.InvoiceController do
  use EdocApiWeb, :controller

  alias EdocApi.Core
  alias EdocApiWeb.PdfTemplates

  def create(conn, params) do
    user = conn.assigns.current_user

    case Core.get_company_by_user_id(user.id) do
      nil ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "company_required"})

      company ->
        case Core.create_invoice_for_user(user.id, company.id, params) do
          {:ok, invoice} ->
            conn
            |> put_status(:created)
            |> json(%{invoice: invoice_json(invoice)})

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "validation_error", details: errors_to_map(changeset)})
        end
    end
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.get_invoice_for_user(user.id, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "invoice_not_found"})

      invoice ->
        json(conn, %{invoice: invoice_json(invoice)})
    end
  end

  def pdf(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    conn = put_layout(conn, false)

    case Core.get_invoice_for_user(user.id, id) do
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

  # -------- helpers --------

  defp invoice_json(inv) do
    %{
      id: inv.id,
      number: inv.number,
      service_name: inv.service_name,
      issue_date: inv.issue_date,
      due_date: inv.due_date,
      currency: inv.currency,
      seller_name: inv.seller_name,
      seller_bin_iin: inv.seller_bin_iin,
      seller_address: inv.seller_address,
      seller_iban: inv.seller_iban,
      buyer_name: inv.buyer_name,
      buyer_bin_iin: inv.buyer_bin_iin,
      buyer_address: inv.buyer_address,
      subtotal: inv.subtotal,
      vat: inv.vat,
      total: inv.total,
      status: inv.status,
      company_id: inv.company_id,
      user_id: inv.user_id,
      inserted_at: inv.inserted_at,
      updated_at: inv.updated_at
    }
  end

  defp errors_to_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
