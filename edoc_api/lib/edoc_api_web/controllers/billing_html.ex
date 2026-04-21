defmodule EdocApiWeb.BillingHTML do
  use EdocApiWeb, :html

  embed_templates("billing_html/*")

  def plan_label(nil), do: "No plan"
  def plan_label(%{name: name}), do: name

  def date_or_dash(nil), do: "-"

  def date_or_dash(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%d.%m.%Y")
  end

  def status_label(nil), do: "-"
  def status_label(status), do: status

  def reminder_title(:overdue_payment), do: "Payment reminder"
  def reminder_title(:subscription_suspended), do: "Subscription suspended"
  def reminder_title(_), do: "Billing reminder"
end
