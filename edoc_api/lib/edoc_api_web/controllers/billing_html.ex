defmodule EdocApiWeb.BillingHTML do
  use EdocApiWeb, :html

  embed_templates("billing_html/*")

  def plan_label(nil), do: gettext("No plan")
  def plan_label(%{code: "trial"}), do: gettext("Trial")
  def plan_label(%{code: "starter"}), do: gettext("Starter")
  def plan_label(%{code: "basic"}), do: gettext("Basic")
  def plan_label(%{name: name}), do: name

  def date_or_dash(nil), do: "-"

  def date_or_dash(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%d.%m.%Y")
  end

  def status_label(nil), do: "-"
  def status_label("trialing"), do: gettext("Trial")
  def status_label("active"), do: gettext("Active")
  def status_label("grace_period"), do: gettext("Grace period")
  def status_label("past_due"), do: gettext("Past due")
  def status_label("suspended"), do: gettext("Suspended")
  def status_label("draft"), do: gettext("Draft")
  def status_label("sent"), do: gettext("Sent")
  def status_label("paid"), do: gettext("Paid")
  def status_label("overdue"), do: gettext("Overdue")
  def status_label("pending_confirmation"), do: gettext("Pending confirmation")
  def status_label(status), do: status

  def reminder_title(:overdue_payment), do: gettext("Payment reminder")
  def reminder_title(:subscription_suspended), do: gettext("Subscription suspended")
  def reminder_title(_), do: gettext("Billing reminder")

  def reminder_message(%{kind: :overdue_payment}) do
    gettext("Billing invoice is overdue. Please pay it or submit payment proof.")
  end

  def reminder_message(%{kind: :subscription_suspended}) do
    gettext("Subscription is suspended until payment is confirmed.")
  end

  def reminder_message(%{message: message}), do: message

  def blocked_reason_label(nil), do: gettext("not specified")
  def blocked_reason_label("payment_overdue"), do: gettext("payment overdue")
  def blocked_reason_label(reason), do: reason
end
