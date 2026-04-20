defmodule EdocApi.Billing do
  @moduledoc """
  Billing context boundary.

  Phase 1 intentionally defines domain language and status boundaries only.
  Persistence, Kaspi payment-link flow, and admin workflows are introduced in
  later phases.
  """

  alias EdocApi.Billing.{BillingInvoiceStatus, PaymentStatus, SubscriptionStatus}

  @responsibilities [
    :plans,
    :subscriptions,
    :billing_invoices,
    :payments,
    :usage_counters,
    :billing_audit_events
  ]

  @tenant_key :company_id

  @doc "Returns the tenant foreign key used by billing records."
  def tenant_key, do: @tenant_key

  @doc "Returns the owned responsibilities of the billing context."
  def responsibilities, do: @responsibilities

  @doc """
  Returns the separate billing state models.

  These states must not be collapsed into a single subscription status. A paid
  subscription, an unpaid billing invoice, and a pending manual payment are
  different records with different lifecycles.
  """
  def state_models do
    %{
      subscription: SubscriptionStatus.all(),
      billing_invoice: BillingInvoiceStatus.all(),
      payment: PaymentStatus.all(),
      usage_tracking: [:usage_events, :usage_counters]
    }
  end
end
