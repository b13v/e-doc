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
      cond do
        invoice.status == "issued" and EdocApi.Invoicing.contract_ready_for_progression?(invoice) ->
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

        invoice.status == "draft" ->
          [
            %{
              label: gettext("Edit"),
              tone: :success,
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

        true ->
          []
      end

    %{primary: primary, secondary: secondary}
  end

  embed_templates("invoices_html/*")
end
