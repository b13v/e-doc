defmodule EdocApiWeb.InvoicesHTML do
  use EdocApiWeb, :html

  def issue_date_text(nil), do: "-"
  def issue_date_text(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")

  def row_actions(invoice) do
    primary = %{
      label: gettext("View"),
      tone: :info,
      transport: :link,
      method: :get,
      href: "/invoices/#{invoice.id}"
    }

    secondary =
      case invoice.status do
        "issued" ->
          [
            %{
              label: gettext("Paid"),
              tone: :success,
              transport: :form,
              method: :post,
              action: "/invoices/#{invoice.id}/pay",
              confirm_text: gettext("Mark this invoice as paid?")
            }
          ]

        "draft" ->
          [
            %{
              label: gettext("Edit"),
              transport: :link,
              method: :get,
              href: "/invoices/#{invoice.id}/edit"
            },
            %{
              label: gettext("Delete"),
              tone: :danger,
              transport: :htmx_delete,
              method: :delete,
              hx_delete: "/invoices/#{invoice.id}",
              row_dom_id: "invoice-#{invoice.id}",
              confirm_text: gettext("Delete this invoice?")
            }
          ]

        _ ->
          []
      end

    %{primary: primary, secondary: secondary}
  end

  embed_templates("invoices_html/*")
end
