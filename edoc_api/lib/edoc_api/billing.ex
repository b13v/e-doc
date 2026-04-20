defmodule EdocApi.Billing do
  @moduledoc """
  Billing context boundary.

  Phase 1 intentionally defines domain language and status boundaries only.
  Persistence, Kaspi payment-link flow, and admin workflows are introduced in
  later phases.
  """

  alias EdocApi.Billing.{BillingInvoiceStatus, PaymentStatus, Plan, SubscriptionStatus}
  alias EdocApi.Repo

  @responsibilities [
    :plans,
    :subscriptions,
    :billing_invoices,
    :payments,
    :usage_counters,
    :billing_audit_events
  ]

  @tenant_key :company_id

  @default_plans [
    %{
      code: "trial",
      name: "Trial",
      price_kzt: 0,
      monthly_document_limit: 10,
      included_users: 2,
      is_active: true
    },
    %{
      code: "starter",
      name: "Starter",
      price_kzt: 9_900,
      monthly_document_limit: 50,
      included_users: 2,
      is_active: true
    },
    %{
      code: "basic",
      name: "Basic",
      price_kzt: 29_900,
      monthly_document_limit: 500,
      included_users: 5,
      is_active: true
    }
  ]

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

  @doc "Returns the default SaaS plan definitions used by seeds."
  def default_plans, do: @default_plans

  @doc "Seeds the canonical billing plans idempotently."
  def seed_default_plans do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(@default_plans, fn attrs ->
        attrs
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    {count, _} =
      Repo.insert_all(Plan, rows,
        on_conflict:
          {:replace,
           [:name, :price_kzt, :monthly_document_limit, :included_users, :is_active, :updated_at]},
        conflict_target: [:code]
      )

    {:ok, %{count: count}}
  end
end
