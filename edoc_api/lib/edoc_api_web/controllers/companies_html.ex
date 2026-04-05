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

  def membership_email(%{invite_email: invite_email, user: user}) do
    invite_email || (user && user.email) || "-"
  end

  def membership_role_label("owner"), do: gettext("Owner")
  def membership_role_label("admin"), do: gettext("Admin")
  def membership_role_label("member"), do: gettext("Member")
  def membership_role_label(other), do: other

  def membership_status_label("active"), do: gettext("Active")
  def membership_status_label("invited"), do: gettext("Invited")
  def membership_status_label("pending_seat"), do: gettext("Pending seat")
  def membership_status_label("removed"), do: gettext("Removed")
  def membership_status_label(other), do: other

  def membership_status_reason("pending_seat"),
    do: gettext("Invite accepted, but no seats are available right now.")

  def membership_status_reason(_), do: nil

  def subscription_plan_label("starter"), do: gettext("Starter")
  def subscription_plan_label("basic"), do: gettext("Basic")
  def subscription_plan_label("trial"), do: gettext("Trial")
  def subscription_plan_label(_plan), do: gettext("Starter")

  embed_templates("companies_html/*")
end
