defmodule EdocApiWeb.BuyerHTML do
  use EdocApiWeb, :html

  def legal_form_text(nil), do: nil
  def legal_form_text(value), do: EdocApi.LegalForms.display(value)

  def row_actions(buyer) do
    %{
      primary: %{
        label: gettext("View"),
        tone: :info,
        transport: :link,
        method: :get,
        href: "/buyers/#{buyer.id}"
      },
      secondary: [
        %{
          label: gettext("Edit"),
          tone: :success,
          transport: :link,
          method: :get,
          href: "/buyers/#{buyer.id}/edit"
        },
        %{
          label: gettext("Delete"),
          tone: :danger,
          transport: :form,
          method: :post,
          action: "/buyers/#{buyer.id}",
          _method: "delete",
          confirm_text: gettext("Are you sure you want to delete this buyer?")
        }
      ]
    }
  end

  embed_templates("buyer_html/*")
end
