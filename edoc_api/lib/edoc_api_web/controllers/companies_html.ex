defmodule EdocApiWeb.CompaniesHTML do
  use EdocApiWeb, :html

  def bank_account_row_actions(account, account_count) do
    primary = %{
      label: gettext("View"),
      transport: :link,
      method: :get,
      href: "/company/bank-accounts/#{account.id}"
    }

    secondary =
      [
        %{
          label: gettext("Edit"),
          transport: :link,
          method: :get,
          href: "/company/bank-accounts/#{account.id}/edit"
        }
      ] ++ delete_action(account, account_count)

    %{primary: primary, secondary: secondary}
  end

  defp delete_action(_account, account_count) when account_count <= 1, do: []

  defp delete_action(account, _account_count) do
    [
      %{
        label: gettext("Delete"),
        transport: :form,
        method: :post,
        action: "/company/bank-accounts/#{account.id}",
        _method: "delete",
        confirm_text: gettext("Are you sure you want to delete this bank account?")
      }
    ]
  end

  embed_templates("companies_html/*")
end
