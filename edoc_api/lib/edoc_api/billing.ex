defmodule EdocApi.Billing do
  @moduledoc """
  Billing context boundary.

  Phase 1 intentionally defines domain language and status boundaries only.
  Persistence, Kaspi payment-link flow, and admin workflows are introduced in
  later phases.
  """

  import Ecto.Query

  alias EdocApi.Billing.{
    BillingInvoice,
    BillingInvoiceStatus,
    Payment,
    PaymentStatus,
    Plan,
    Subscription,
    SubscriptionStatus,
    UsageCounter,
    UsageEvent
  }

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

  @current_subscription_statuses [
    SubscriptionStatus.trialing(),
    SubscriptionStatus.active(),
    SubscriptionStatus.grace_period(),
    SubscriptionStatus.past_due(),
    SubscriptionStatus.suspended()
  ]

  @billable_document_metric "billable_documents"

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

  @doc "Lists active plans in canonical display order."
  def list_active_plans do
    Plan
    |> where([p], p.is_active == true)
    |> order_by(
      [p],
      fragment(
        "CASE ? WHEN 'trial' THEN 0 WHEN 'starter' THEN 1 WHEN 'basic' THEN 2 ELSE 99 END",
        p.code
      )
    )
    |> Repo.all()
  end

  @doc "Looks up an active plan by normalized code."
  def get_plan_by_code(code) do
    case Repo.get_by(Plan, code: normalize_code(code), is_active: true) do
      nil -> {:error, :not_found}
      plan -> {:ok, plan}
    end
  end

  @doc "Returns the current non-canceled subscription for a company."
  def get_current_subscription(company_or_id) do
    company_id = record_id(company_or_id)

    Subscription
    |> where([s], s.company_id == ^company_id and s.status in ^@current_subscription_statuses)
    |> preload([:plan, :next_plan])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      subscription -> {:ok, subscription}
    end
  end

  @doc "Creates a 14-day trial subscription for a tenant."
  def create_trial_subscription(company_or_id, opts \\ []) do
    with {:ok, trial_plan} <- get_plan_by_code("trial"),
         {:error, :not_found} <- get_current_subscription(company_or_id) do
      now = billing_now(opts)

      %Subscription{}
      |> Subscription.changeset(%{
        company_id: record_id(company_or_id),
        plan_id: trial_plan.id,
        status: SubscriptionStatus.trialing(),
        current_period_start: now,
        current_period_end: DateTime.add(now, 14, :day),
        auto_renew_mode: "manual"
      })
      |> Repo.insert()
      |> preload_subscription_result()
    else
      {:ok, %Subscription{} = subscription} -> {:ok, subscription}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Activates a subscription on the given plan."
  def activate_subscription(subscription_or_id, plan_or_code, opts \\ []) do
    with %Subscription{} = subscription <- get_subscription!(subscription_or_id),
         {:ok, plan} <- resolve_plan(plan_or_code) do
      now = billing_now(opts)
      period_start = Keyword.get(opts, :period_start, now)
      period_end = Keyword.get(opts, :period_end, DateTime.add(period_start, 30, :day))

      update_subscription(subscription, %{
        plan_id: plan.id,
        status: SubscriptionStatus.active(),
        current_period_start: period_start,
        current_period_end: period_end,
        grace_until: nil,
        blocked_reason: nil
      })
    end
  end

  @doc "Moves a subscription into grace period until the given datetime."
  def move_subscription_to_grace_period(subscription_or_id, grace_until) do
    subscription_or_id
    |> get_subscription!()
    |> update_subscription(%{
      status: SubscriptionStatus.grace_period(),
      grace_until: grace_until,
      blocked_reason: nil
    })
  end

  @doc "Suspends a subscription with a machine-readable reason."
  def suspend_subscription(subscription_or_id, reason) do
    subscription_or_id
    |> get_subscription!()
    |> update_subscription(%{
      status: SubscriptionStatus.suspended(),
      blocked_reason: reason
    })
  end

  @doc "Extends or replaces a subscription period."
  def renew_subscription(subscription_or_id, opts) do
    subscription_or_id
    |> get_subscription!()
    |> update_subscription(%{
      status: SubscriptionStatus.active(),
      current_period_start: Keyword.fetch!(opts, :period_start),
      current_period_end: Keyword.fetch!(opts, :period_end),
      grace_until: nil,
      blocked_reason: nil
    })
  end

  @doc "Schedules a plan change for the end of the current billing period."
  def schedule_plan_change(subscription_or_id, plan_or_code, effective_at) do
    with %Subscription{} = subscription <- get_subscription!(subscription_or_id),
         {:ok, plan} <- resolve_plan(plan_or_code) do
      update_subscription(subscription, %{
        next_plan_id: plan.id,
        change_effective_at: effective_at
      })
    end
  end

  @doc "Returns the document limit for the tenant's current plan."
  def allowed_document_limit(company_or_id) do
    with {:ok, subscription} <- get_current_subscription(company_or_id) do
      {:ok, subscription.plan.monthly_document_limit}
    end
  end

  @doc "Returns the user-seat limit for the tenant's current plan."
  def allowed_user_limit(company_or_id) do
    with {:ok, subscription} <- get_current_subscription(company_or_id) do
      {:ok, subscription.plan.included_users + subscription.extra_user_seats}
    end
  end

  @doc "Returns the current-period billable document usage."
  def current_document_usage(company_or_id) do
    with {:ok, subscription} <- get_current_subscription(company_or_id) do
      value =
        UsageCounter
        |> where(
          [c],
          c.company_id == ^record_id(company_or_id) and c.metric == ^@billable_document_metric and
            c.period_start == ^subscription.current_period_start and
            c.period_end == ^subscription.current_period_end
        )
        |> select([c], c.value)
        |> Repo.one()

      {:ok, value || 0}
    end
  end

  @doc "Records billable document usage and increments the current-period counter."
  def record_document_usage(company_or_id, resource_type, resource_id, opts \\ []) do
    with {:ok, subscription} <- get_current_subscription(company_or_id) do
      company_id = record_id(company_or_id)
      count = Keyword.get(opts, :count, 1)

      Repo.transaction(fn ->
        event =
          %UsageEvent{}
          |> UsageEvent.changeset(%{
            company_id: company_id,
            metric: @billable_document_metric,
            resource_type: resource_type,
            resource_id: resource_id,
            count: count,
            occurred_at: Keyword.get(opts, :occurred_at),
            period_start: subscription.current_period_start,
            period_end: subscription.current_period_end
          })
          |> Repo.insert!()

        upsert_usage_counter!(
          company_id,
          subscription.current_period_start,
          subscription.current_period_end,
          count
        )

        event
      end)
    end
  end

  @doc "Creates a draft renewal billing invoice."
  def create_renewal_invoice(subscription_or_id, plan_or_code, opts \\ []) do
    create_billing_invoice(subscription_or_id, plan_or_code, "renewal", opts)
  end

  @doc "Creates a draft upgrade billing invoice."
  def create_upgrade_invoice(subscription_or_id, plan_or_code, opts \\ []) do
    create_billing_invoice(subscription_or_id, plan_or_code, "upgrade", opts)
  end

  @doc "Marks a draft billing invoice as sent."
  def send_billing_invoice(invoice_or_id, opts \\ []) do
    invoice_or_id
    |> get_billing_invoice!()
    |> update_billing_invoice(%{
      status: BillingInvoiceStatus.sent(),
      payment_method: Keyword.get(opts, :payment_method),
      kaspi_payment_link: Keyword.get(opts, :kaspi_payment_link),
      issued_at: billing_now(opts)
    })
  end

  @doc "Marks a sent billing invoice as overdue."
  def mark_billing_invoice_overdue(invoice_or_id, _opts \\ []) do
    invoice_or_id
    |> get_billing_invoice!()
    |> update_billing_invoice(%{status: BillingInvoiceStatus.overdue()})
  end

  @doc "Creates a pending payment for a billing invoice."
  def create_payment(invoice_or_id, opts \\ []) do
    invoice = get_billing_invoice!(invoice_or_id)

    %Payment{}
    |> Payment.changeset(%{
      company_id: invoice.company_id,
      billing_invoice_id: invoice.id,
      amount_kzt: Keyword.get(opts, :amount_kzt, invoice.amount_kzt),
      method: Keyword.get(opts, :method, "manual"),
      status: PaymentStatus.pending_confirmation(),
      paid_at: Keyword.get(opts, :paid_at),
      external_reference: Keyword.get(opts, :external_reference),
      proof_attachment_url: Keyword.get(opts, :proof_attachment_url)
    })
    |> Repo.insert()
  end

  @doc "Confirms a pending manual payment and activates the paid subscription period."
  def confirm_manual_payment(payment_or_id, admin_user_or_id, opts \\ []) do
    now = billing_now(opts)
    admin_user_id = record_id(admin_user_or_id)

    Repo.transaction(fn ->
      payment = get_payment!(payment_or_id)

      if payment.status == PaymentStatus.confirmed() do
        invoice = get_billing_invoice!(payment.billing_invoice_id)
        subscription = get_subscription!(invoice.subscription_id)
        %{payment: payment, invoice: invoice, subscription: subscription}
      else
        invoice = get_billing_invoice!(payment.billing_invoice_id)
        subscription = get_subscription!(invoice.subscription_id)
        {:ok, plan} = resolve_plan(invoice.plan_snapshot_code)

        confirmed_payment =
          payment
          |> Payment.changeset(%{
            status: PaymentStatus.confirmed(),
            confirmed_at: now,
            confirmed_by_user_id: admin_user_id
          })
          |> Repo.update!()

        paid_invoice =
          invoice
          |> BillingInvoice.changeset(%{
            status: BillingInvoiceStatus.paid(),
            paid_at: now,
            activated_by_user_id: admin_user_id
          })
          |> Repo.update!()

        active_subscription =
          subscription
          |> Subscription.changeset(%{
            plan_id: plan.id,
            status: SubscriptionStatus.active(),
            current_period_start: invoice.period_start,
            current_period_end: invoice.period_end,
            grace_until: nil,
            blocked_reason: nil
          })
          |> Repo.update!()
          |> Repo.preload([:plan, :next_plan], force: true)

        %{payment: confirmed_payment, invoice: paid_invoice, subscription: active_subscription}
      end
    end)
  end

  @doc "Rejects a pending payment without activating the subscription."
  def reject_payment(payment_or_id, admin_user_or_id, opts \\ []) do
    payment_or_id
    |> get_payment!()
    |> Payment.changeset(%{
      status: PaymentStatus.rejected(),
      confirmed_at: billing_now(opts),
      confirmed_by_user_id: record_id(admin_user_or_id)
    })
    |> Repo.update()
  end

  defp create_billing_invoice(subscription_or_id, plan_or_code, note, opts) do
    with %Subscription{} = subscription <- get_subscription!(subscription_or_id),
         {:ok, plan} <- resolve_plan(plan_or_code) do
      period_start = Keyword.get(opts, :period_start, subscription.current_period_end)
      period_end = Keyword.get(opts, :period_end, DateTime.add(period_start, 30, :day))

      %BillingInvoice{}
      |> BillingInvoice.changeset(%{
        company_id: subscription.company_id,
        subscription_id: subscription.id,
        period_start: period_start,
        period_end: period_end,
        plan_snapshot_code: plan.code,
        amount_kzt: Keyword.get(opts, :amount_kzt, plan.price_kzt),
        status: BillingInvoiceStatus.draft(),
        due_at: Keyword.get(opts, :due_at),
        note: note
      })
      |> Repo.insert()
    end
  end

  defp update_subscription(subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
    |> preload_subscription_result()
  end

  defp update_billing_invoice(invoice, attrs) do
    invoice
    |> BillingInvoice.changeset(attrs)
    |> Repo.update()
  end

  defp upsert_usage_counter!(company_id, period_start, period_end, count) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      UsageCounter,
      [
        %{
          id: Ecto.UUID.generate(),
          company_id: company_id,
          metric: @billable_document_metric,
          period_start: period_start,
          period_end: period_end,
          value: count,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [inc: [value: count], set: [updated_at: now]],
      conflict_target: [:company_id, :metric, :period_start, :period_end]
    )
  end

  defp preload_subscription_result({:ok, subscription}) do
    {:ok, Repo.preload(subscription, [:plan, :next_plan], force: true)}
  end

  defp preload_subscription_result(other), do: other

  defp get_subscription!(%Subscription{} = subscription), do: subscription
  defp get_subscription!(id), do: Repo.get!(Subscription, id) |> Repo.preload([:plan, :next_plan])

  defp get_billing_invoice!(%BillingInvoice{} = invoice), do: invoice
  defp get_billing_invoice!(id), do: Repo.get!(BillingInvoice, id)

  defp get_payment!(%Payment{id: id}), do: Repo.get!(Payment, id)
  defp get_payment!(id), do: Repo.get!(Payment, id)

  defp resolve_plan(%Plan{} = plan), do: {:ok, plan}
  defp resolve_plan(code), do: get_plan_by_code(code)

  defp normalize_code(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_code(value), do: value

  defp record_id(%{id: id}), do: id
  defp record_id(id), do: id

  defp billing_now(opts) do
    opts
    |> Keyword.get(:now, DateTime.utc_now())
    |> DateTime.truncate(:second)
  end
end
