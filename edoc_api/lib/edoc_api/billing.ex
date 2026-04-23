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
    BillingAuditEvent,
    Payment,
    PaymentStatus,
    Plan,
    Subscription,
    SubscriptionStatus,
    UsageCounter,
    UsageEvent
  }

  alias EdocApi.Accounts.User
  alias EdocApi.Core.{Company, TenantMembership, TenantSubscription, TenantUsageEvent}
  alias EdocApi.EmailSender
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
  @occupied_membership_statuses ["active", "invited", "pending_seat"]
  @renewal_invoice_lead_days 7
  @overdue_grace_days 7
  @plan_rank %{"trial" => 0, "starter" => 1, "basic" => 2}
  @renewal_reminder_days %{
    7 => :renewal_7_day,
    3 => :renewal_3_day,
    0 => :renewal_due_today
  }

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

  @doc "Schedules a downgrade for the next billing cycle when current usage fits the target plan."
  def schedule_downgrade(subscription_or_id, plan_or_code, effective_at) do
    with %Subscription{} = subscription <- get_subscription!(subscription_or_id),
         {:ok, target_plan} <- resolve_plan(plan_or_code),
         :ok <- ensure_plan_direction(subscription.plan, target_plan, :downgrade),
         :ok <- ensure_target_plan_can_hold_current_seats(subscription, target_plan),
         :ok <- ensure_target_plan_can_hold_current_usage(subscription, target_plan) do
      schedule_plan_change(subscription, target_plan, effective_at)
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
      {:ok, subscription.plan.included_users}
    end
  end

  @doc "Returns the current-period billable document usage."
  def current_document_usage(company_or_id) do
    with {:ok, subscription} <- get_current_subscription(company_or_id) do
      {:ok, current_document_usage_for_subscription(record_id(company_or_id), subscription)}
    end
  end

  @doc "Returns true when the tenant is allowed to create another billable document."
  def can_create_document?(company_or_id) do
    case ensure_can_create_document(company_or_id) do
      {:ok, _quota} -> true
      {:error, _reason, _details} -> false
      {:error, _reason} -> false
    end
  end

  @doc "Returns current quota details or a domain error explaining why creation is blocked."
  def ensure_can_create_document(company_or_id) do
    with {:ok, subscription} <- get_current_subscription(company_or_id),
         :ok <- ensure_subscription_allows_creation(subscription),
         {:ok, used} <- current_document_usage(company_or_id) do
      limit = subscription.plan.monthly_document_limit
      remaining = max(limit - used, 0)

      if used >= limit do
        {:error, :quota_exceeded, document_quota_details(subscription, used, limit, remaining)}
      else
        {:ok, document_quota_details(subscription, used, limit, remaining)}
      end
    end
  end

  @doc "Raises when document creation is not allowed; returns quota details otherwise."
  def ensure_can_create_document!(company_or_id) do
    case ensure_can_create_document(company_or_id) do
      {:ok, quota} ->
        quota

      {:error, reason, details} ->
        raise "billing document creation blocked: #{inspect({reason, details})}"

      {:error, reason} ->
        raise "billing document creation blocked: #{inspect(reason)}"
    end
  end

  @doc "Records billable document usage and increments the current-period counter."
  def record_document_usage(company_or_id, resource_type, resource_id, opts \\ []) do
    count = Keyword.get(opts, :count, 1)

    with {:ok, subscription} <- get_current_subscription(company_or_id) do
      company_id = record_id(company_or_id)

      Repo.transaction(fn ->
        subscription =
          Subscription
          |> where([s], s.id == ^subscription.id)
          |> lock("FOR UPDATE")
          |> Repo.one!()
          |> Repo.preload([:plan, :next_plan], force: true)

        with :ok <- ensure_subscription_allows_creation(subscription),
             {:ok, _quota} <-
               ensure_can_record_document_usage_locked(company_id, subscription, count) do
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
        else
          {:error, reason, details} -> Repo.rollback({:error, reason, details})
          {:error, reason} -> Repo.rollback({:error, reason})
        end
      end)
      |> case do
        {:ok, event} -> {:ok, event}
        {:error, {:error, reason, details}} -> {:error, reason, details}
        {:error, {:error, reason}} -> {:error, reason}
        other -> other
      end
    end
  end

  defp ensure_can_record_document_usage_locked(company_id, subscription, count) do
    used = current_document_usage_for_subscription(company_id, subscription)
    limit = subscription.plan.monthly_document_limit
    remaining = max(limit - used, 0)

    if used + count > limit do
      {:error, :quota_exceeded, document_quota_details(subscription, used, limit, remaining)}
    else
      {:ok, document_quota_details(subscription, used, limit, remaining)}
    end
  end

  defp current_document_usage_for_subscription(company_id, subscription) do
    value =
      UsageCounter
      |> where(
        [c],
        c.company_id == ^company_id and c.metric == ^@billable_document_metric and
          c.period_start == ^subscription.current_period_start and
          c.period_end == ^subscription.current_period_end
      )
      |> select([c], c.value)
      |> Repo.one()

    value || 0
  end

  @doc "Returns true when the tenant can occupy another user seat."
  def can_add_user?(company_or_id) do
    case ensure_can_add_user(company_or_id) do
      {:ok, _details} -> true
      {:error, _reason, _details} -> false
      {:error, _reason} -> false
    end
  end

  @doc "Returns current seat details or a domain error explaining why adding a user is blocked."
  def ensure_can_add_user(company_or_id) do
    with {:ok, subscription} <- get_current_subscription(company_or_id) do
      company_id = record_id(company_or_id)
      used = occupied_seat_count(company_id)
      limit = subscription.plan.included_users
      remaining = max(limit - used, 0)
      details = seat_quota_details(subscription, used, limit, remaining)

      if used >= limit do
        {:error, :seat_limit_reached, details}
      else
        {:ok, details}
      end
    end
  end

  @doc "Raises when a user seat cannot be added; returns seat details otherwise."
  def ensure_can_add_user!(company_or_id) do
    case ensure_can_add_user(company_or_id) do
      {:ok, details} -> details
      {:error, reason, details} -> raise "billing seat blocked: #{inspect({reason, details})}"
      {:error, reason} -> raise "billing seat blocked: #{inspect(reason)}"
    end
  end

  @doc "Creates a draft renewal billing invoice."
  def create_renewal_invoice(subscription_or_id, plan_or_code, opts \\ []) do
    create_billing_invoice(subscription_or_id, plan_or_code, "renewal", opts)
  end

  @doc """
  Creates renewal invoices for active subscriptions that are inside the renewal lead window.

  The job is idempotent at the application level: if a non-canceled renewal
  invoice already exists for the same subscription and renewal period, it is
  returned in `:skipped` instead of creating a duplicate.
  """
  def generate_renewal_invoices(opts \\ []) do
    now = billing_now(opts)
    lead_days = Keyword.get(opts, :lead_days, @renewal_invoice_lead_days)
    horizon = DateTime.add(now, lead_days, :day)

    Subscription
    |> where([s], s.status == ^SubscriptionStatus.active())
    |> where([s], s.current_period_end <= ^horizon)
    |> where([s], s.current_period_end > ^now)
    |> preload([:plan, :next_plan])
    |> Repo.all()
    |> Enum.reduce(%{created: [], skipped: []}, fn subscription, acc ->
      case create_due_renewal_invoice(subscription) do
        {:ok, %BillingInvoice{} = invoice} -> update_in(acc.created, &[invoice | &1])
        {:skipped, %BillingInvoice{} = invoice} -> update_in(acc.skipped, &[invoice | &1])
        {:error, _changeset} -> update_in(acc.skipped, & &1)
      end
    end)
    |> reverse_lifecycle_result_lists()
  end

  @doc "Creates a draft upgrade billing invoice."
  def create_upgrade_invoice(subscription_or_id, plan_or_code, opts \\ []) do
    create_billing_invoice(subscription_or_id, plan_or_code, "upgrade", opts)
  end

  @doc "Creates an immediate upgrade invoice for the remainder of the current period."
  def create_immediate_upgrade_invoice(subscription_or_id, plan_or_code, opts \\ []) do
    with %Subscription{} = subscription <- get_subscription!(subscription_or_id),
         {:ok, target_plan} <- resolve_plan(plan_or_code),
         :ok <- ensure_plan_direction(subscription.plan, target_plan, :upgrade) do
      now = billing_now(opts)

      create_upgrade_invoice(subscription, target_plan,
        period_start: now,
        period_end: subscription.current_period_end,
        due_at: Keyword.get(opts, :due_at)
      )
    end
  end

  @doc "Creates an immediate upgrade invoice scoped to a tenant company."
  def create_upgrade_invoice_for_company(company_or_id, plan_or_code, opts \\ []) do
    with {:ok, subscription} <- get_current_subscription(company_or_id) do
      create_immediate_upgrade_invoice(subscription, plan_or_code, opts)
    end
  end

  @doc "Marks a draft billing invoice as sent."
  def send_billing_invoice(invoice_or_id, opts \\ []) do
    kaspi_payment_link = Keyword.get(opts, :kaspi_payment_link)
    payment_method = Keyword.get(opts, :payment_method) || if kaspi_payment_link, do: "kaspi_link"

    invoice_or_id
    |> get_billing_invoice!()
    |> update_billing_invoice(%{
      status: BillingInvoiceStatus.sent(),
      payment_method: payment_method,
      kaspi_payment_link: kaspi_payment_link,
      issued_at: billing_now(opts)
    })
  end

  @doc "Marks a sent billing invoice as overdue."
  def mark_billing_invoice_overdue(invoice_or_id, _opts \\ []) do
    invoice_or_id
    |> get_billing_invoice!()
    |> update_billing_invoice(%{status: BillingInvoiceStatus.overdue()})
  end

  @doc """
  Marks due sent invoices as overdue and starts a grace period for their subscriptions.
  """
  def process_overdue_billing(opts \\ []) do
    now = billing_now(opts)

    BillingInvoice
    |> where([i], i.status == ^BillingInvoiceStatus.sent())
    |> where([i], not is_nil(i.due_at) and i.due_at < ^now)
    |> order_by([i], asc: i.due_at)
    |> Repo.all()
    |> Enum.reduce(%{overdue_invoices: [], graced_subscriptions: []}, fn invoice, acc ->
      {:ok, overdue_invoice} = mark_billing_invoice_overdue(invoice)

      subscription =
        invoice.subscription_id
        |> get_subscription!()
        |> maybe_move_to_overdue_grace(invoice.due_at)

      acc
      |> update_in([:overdue_invoices], &[overdue_invoice | &1])
      |> maybe_collect_subscription(:graced_subscriptions, subscription)
    end)
    |> reverse_lifecycle_result_lists()
  end

  @doc "Suspends subscriptions whose billing grace period has expired."
  def process_grace_expirations(opts \\ []) do
    now = billing_now(opts)

    Subscription
    |> where([s], s.status == ^SubscriptionStatus.grace_period())
    |> where([s], not is_nil(s.grace_until) and s.grace_until < ^now)
    |> preload([:plan, :next_plan])
    |> Repo.all()
    |> Enum.reduce(%{suspended_subscriptions: []}, fn subscription, acc ->
      {:ok, suspended} = suspend_subscription(subscription, "payment_overdue")
      update_in(acc.suspended_subscriptions, &[suspended | &1])
    end)
    |> reverse_lifecycle_result_lists()
  end

  @doc "Sends idempotent tenant and internal billing reminders for the current lifecycle date."
  def send_billing_reminders(opts \\ []) do
    now = billing_now(opts)

    %{
      renewal_7_day: send_renewal_reminders(now, 7),
      renewal_3_day: send_renewal_reminders(now, 3),
      renewal_due_today: send_renewal_reminders(now, 0),
      overdue: send_overdue_invoice_reminders(now),
      suspended: send_suspended_subscription_notices(now),
      admin_high_value_overdue: send_high_value_overdue_alerts(now)
    }
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

  @doc "Attaches a Kaspi payment link and marks the invoice payment method accordingly."
  def attach_kaspi_payment_link(invoice_or_id, kaspi_payment_link) do
    invoice_or_id
    |> get_billing_invoice!()
    |> update_billing_invoice(%{
      payment_method: "kaspi_link",
      kaspi_payment_link: kaspi_payment_link
    })
  end

  @doc "Creates a customer-submitted pending payment review with optional proof and note."
  def create_customer_payment_review(invoice_or_id, attrs) when is_map(attrs) do
    invoice = get_billing_invoice!(invoice_or_id)
    method = invoice.payment_method || "manual"

    Repo.transaction(fn ->
      payment =
        %Payment{}
        |> Payment.changeset(%{
          company_id: invoice.company_id,
          billing_invoice_id: invoice.id,
          amount_kzt: invoice.amount_kzt,
          method: method,
          status: PaymentStatus.pending_confirmation(),
          paid_at: DateTime.utc_now() |> DateTime.truncate(:second),
          external_reference:
            normalize_blank(
              Map.get(attrs, "external_reference") || Map.get(attrs, :external_reference)
            ),
          proof_attachment_url:
            normalize_blank(
              Map.get(attrs, "proof_attachment_url") || Map.get(attrs, :proof_attachment_url)
            )
        })
        |> Repo.insert!()

      note = normalize_blank(Map.get(attrs, "note") || Map.get(attrs, :note))

      if note do
        %BillingAuditEvent{}
        |> BillingAuditEvent.changeset(%{
          company_id: invoice.company_id,
          action: "payment_review_note",
          subject_type: "payment",
          subject_id: payment.id,
          metadata: %{note: note}
        })
        |> Repo.insert!()
      end

      payment
    end)
  end

  @doc "Creates a customer payment review only when the invoice belongs to the company."
  def create_customer_payment_review_for_company(company_or_id, invoice_id, attrs)
      when is_binary(invoice_id) and is_map(attrs) do
    case Repo.get_by(BillingInvoice, id: invoice_id, company_id: record_id(company_or_id)) do
      nil -> {:error, :not_found}
      invoice -> create_customer_payment_review(invoice, attrs)
    end
  end

  @doc "Confirms a pending manual payment and activates the paid subscription period."
  def confirm_manual_payment(payment_or_id, admin_user_or_id, opts \\ []) do
    now = billing_now(opts)
    admin_user_id = record_id(admin_user_or_id)

    Repo.transaction(fn ->
      payment = get_payment_for_update!(payment_or_id)

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
            blocked_reason: nil,
            next_plan_id: nil,
            change_effective_at: nil
          })
          |> Repo.update!()
          |> Repo.preload([:plan, :next_plan], force: true)

        insert_audit_event!(
          invoice.company_id,
          admin_user_id,
          "payment_confirmed",
          "payment",
          confirmed_payment.id,
          %{
            billing_invoice_id: invoice.id,
            subscription_id: subscription.id,
            amount_kzt: confirmed_payment.amount_kzt,
            confirmed_at: now
          }
        )

        maybe_insert_subscription_status_change!(
          subscription,
          active_subscription,
          %{source: "payment_confirmation", payment_id: confirmed_payment.id, at: now}
        )

        %{payment: confirmed_payment, invoice: paid_invoice, subscription: active_subscription}
      end
    end)
  end

  @doc "Rejects a pending payment without activating the subscription."
  def reject_payment(payment_or_id, admin_user_or_id, opts \\ []) do
    payment = get_payment!(payment_or_id)
    now = billing_now(opts)
    admin_user_id = record_id(admin_user_or_id)

    payment
    |> Payment.changeset(%{
      status: PaymentStatus.rejected(),
      confirmed_at: now,
      confirmed_by_user_id: admin_user_id
    })
    |> Repo.update()
    |> case do
      {:ok, rejected} ->
        insert_audit_event!(
          rejected.company_id,
          admin_user_id,
          "payment_rejected",
          "payment",
          rejected.id,
          %{rejected_at: now, billing_invoice_id: rejected.billing_invoice_id}
        )

        {:ok, rejected}

      other ->
        other
    end
  end

  @doc "Lists client billing summaries for the internal backoffice."
  def list_admin_clients do
    Company
    |> order_by([c], asc: c.name)
    |> preload(:user)
    |> Repo.all()
    |> Enum.map(&admin_client_summary/1)
  end

  @doc "Returns aggregate billing KPIs and operational lists for the internal backoffice."
  def admin_billing_dashboard(opts \\ []) do
    now = billing_now(opts)

    month_start =
      DateTime.new!(Date.beginning_of_month(DateTime.to_date(now)), ~T[00:00:00], "Etc/UTC")

    renewal_horizon = DateTime.add(now, @renewal_invoice_lead_days, :day)

    cards = %{
      active_clients: active_client_count(),
      trial_clients: trial_client_count(),
      overdue_clients: overdue_client_count(),
      suspended_clients: subscription_count(SubscriptionStatus.suspended()),
      monthly_collected_revenue: monthly_collected_revenue(month_start, now),
      upcoming_renewals: upcoming_renewal_count(now, renewal_horizon)
    }

    lists = %{
      invoices_due_soon: invoices_due_soon(now, renewal_horizon),
      unpaid_invoices: unpaid_billing_invoices(),
      recently_reactivated_clients: recently_reactivated_clients(now)
    }

    %{cards: cards, lists: lists}
  end

  @doc "Returns one client billing detail for the internal backoffice."
  def get_admin_client!(company_id) do
    company =
      Company
      |> Repo.get!(company_id)
      |> Repo.preload(:user)

    summary = admin_client_summary(company)

    memberships =
      TenantMembership
      |> where([m], m.company_id == ^company.id and m.status in ^@occupied_membership_statuses)
      |> preload(:user)
      |> order_by([m], asc: m.role, asc: m.invite_email)
      |> Repo.all()

    invoices =
      BillingInvoice
      |> where([i], i.company_id == ^company.id)
      |> order_by([i], desc: i.inserted_at)
      |> preload(:payments)
      |> Repo.all()

    payments =
      Payment
      |> where([p], p.company_id == ^company.id)
      |> order_by([p], desc: p.inserted_at)
      |> Repo.all()

    notes =
      BillingAuditEvent
      |> where([e], e.company_id == ^company.id and e.action == "internal_note")
      |> order_by([e], desc: e.inserted_at)
      |> preload(:actor_user)
      |> Repo.all()

    legacy_pending_invoice =
      if summary.subscription do
        nil
      else
        latest_active_billable_legacy_subscription(company.id)
      end

    Map.merge(summary, %{
      memberships: memberships,
      invoices: invoices,
      payments: payments,
      notes: notes,
      legacy_pending_billing_invoice: legacy_pending_invoice
    })
  end

  @doc "Creates the missing billing invoice for an active legacy tenant subscription."
  def create_legacy_pending_billing_invoice(company_or_id) do
    company_id = record_id(company_or_id)

    with {:ok, legacy_subscription} <- fetch_active_billable_legacy_subscription(company_id),
         {:ok, subscription} <- ensure_current_subscription_from_legacy(legacy_subscription),
         :ok <- ensure_no_legacy_pending_invoice(subscription, legacy_subscription) do
      create_billing_invoice(subscription, legacy_subscription.plan, "legacy_pending",
        period_start: legacy_subscription.period_start,
        period_end: legacy_subscription.period_end,
        due_at: legacy_subscription.period_end
      )
    end
  end

  @doc "Lists billing invoices for backoffice review, optionally filtered by status."
  def list_admin_billing_invoices(filters \\ %{}) do
    status = normalize_blank(Map.get(filters, "status") || Map.get(filters, :status))

    billing_invoices =
      BillingInvoice
      |> maybe_filter_invoice_status(status)
      |> order_by([i], desc: i.inserted_at)
      |> preload([:company, :payments])
      |> Repo.all()

    billing_invoices ++ legacy_pending_billing_invoice_summaries(status)
  end

  @doc "Returns tenant-facing billing data for the current company."
  def tenant_billing_snapshot(company_or_id) do
    company_id = record_id(company_or_id)

    subscription =
      case get_current_subscription(company_id) do
        {:ok, subscription} -> subscription
        {:error, :not_found} -> nil
      end

    legacy_subscription =
      if subscription do
        nil
      else
        latest_legacy_subscription(company_id)
      end

    outstanding_invoices =
      BillingInvoice
      |> where([i], i.company_id == ^company_id and i.status in ^["sent", "overdue"])
      |> order_by([i], asc: i.due_at, desc: i.inserted_at)
      |> preload(:payments)
      |> Repo.all()

    snapshot_subscription = subscription || legacy_subscription_summary(legacy_subscription)

    %{
      subscription: snapshot_subscription,
      plan: tenant_snapshot_plan(subscription, legacy_subscription),
      outstanding_invoices: outstanding_invoices,
      blocked?:
        snapshot_subscription &&
          snapshot_subscription.status in ["past_due", "suspended", "canceled"],
      overdue?: Enum.any?(outstanding_invoices, &(&1.status == "overdue")),
      reminders: tenant_billing_reminders(subscription, outstanding_invoices)
    }
  end

  defp latest_legacy_subscription(company_id) do
    TenantSubscription
    |> where([s], s.company_id == ^company_id and s.status in ["active", "past_due"])
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp latest_active_billable_legacy_subscription(company_id) do
    TenantSubscription
    |> where([s], s.company_id == ^company_id)
    |> where([s], s.status == "active" and s.plan in ["starter", "basic"])
    |> order_by([s], desc: s.period_end, desc: s.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp fetch_active_billable_legacy_subscription(company_id) do
    case latest_active_billable_legacy_subscription(company_id) do
      nil -> {:error, :legacy_subscription_not_found}
      subscription -> {:ok, subscription}
    end
  end

  defp ensure_current_subscription_from_legacy(%TenantSubscription{} = legacy_subscription) do
    case get_current_subscription(legacy_subscription.company_id) do
      {:ok, subscription} ->
        {:ok, subscription}

      {:error, :not_found} ->
        with {:ok, plan} <- resolve_plan(legacy_subscription.plan) do
          %Subscription{}
          |> Subscription.changeset(%{
            company_id: legacy_subscription.company_id,
            plan_id: plan.id,
            status: SubscriptionStatus.active(),
            current_period_start: legacy_subscription.period_start,
            current_period_end: legacy_subscription.period_end,
            auto_renew_mode: "manual"
          })
          |> Repo.insert()
          |> preload_subscription_result()
        end
    end
  end

  defp ensure_no_legacy_pending_invoice(
         %Subscription{} = subscription,
         %TenantSubscription{} = legacy_subscription
       ) do
    existing =
      BillingInvoice
      |> where([i], i.company_id == ^legacy_subscription.company_id)
      |> where([i], i.subscription_id == ^subscription.id)
      |> where(
        [i],
        i.period_start == ^legacy_subscription.period_start and
          i.period_end == ^legacy_subscription.period_end
      )
      |> where([i], i.status != ^BillingInvoiceStatus.canceled())
      |> Repo.exists?()

    if existing do
      {:error, :billing_invoice_already_exists}
    else
      :ok
    end
  end

  defp legacy_subscription_summary(nil), do: nil

  defp legacy_subscription_summary(%TenantSubscription{} = subscription) do
    %{
      status: subscription.status,
      current_period_start: subscription.period_start,
      current_period_end: subscription.period_end,
      blocked_reason: nil
    }
  end

  defp tenant_snapshot_plan(%Subscription{plan: plan}, _legacy_subscription), do: plan
  defp tenant_snapshot_plan(nil, nil), do: nil

  defp tenant_snapshot_plan(nil, %TenantSubscription{plan: plan_code}) do
    plan_code = normalize_code(plan_code)

    @default_plans
    |> Enum.find(%{code: plan_code, name: String.capitalize(plan_code)}, &(&1.code == plan_code))
    |> Map.take([:code, :name, :price_kzt, :monthly_document_limit, :included_users])
  end

  @doc "Adds an internal admin note to the billing audit stream."
  def add_internal_note(company_or_id, actor_user_or_id, note) when is_binary(note) do
    company_id = record_id(company_or_id)
    actor_user_id = record_id(actor_user_or_id)

    %BillingAuditEvent{}
    |> BillingAuditEvent.changeset(%{
      company_id: company_id,
      actor_user_id: actor_user_id,
      action: "internal_note",
      subject_type: "company",
      subject_id: company_id,
      metadata: %{note: String.trim(note)}
    })
    |> Repo.insert()
  end

  @doc "Records an operator/admin billing action in the audit stream."
  def log_admin_billing_action(
        company_or_id,
        actor_user_or_id,
        action,
        subject_type,
        subject_id,
        metadata \\ %{}
      ) do
    %BillingAuditEvent{}
    |> BillingAuditEvent.changeset(%{
      company_id: record_id(company_or_id),
      actor_user_id: record_id(actor_user_or_id),
      action: action,
      subject_type: subject_type,
      subject_id: record_id(subject_id),
      metadata: stringify_metadata_values(metadata)
    })
    |> Repo.insert()
  end

  @doc "Lists internal payment-review notes for a payment."
  def list_payment_review_notes(payment_or_id) do
    payment_id = record_id(payment_or_id)

    BillingAuditEvent
    |> where(
      [e],
      e.subject_type == "payment" and e.subject_id == ^payment_id and
        e.action == "payment_review_note"
    )
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc "Updates a billing invoice payment link and optional due date without changing status."
  def update_invoice_payment_link(invoice_or_id, attrs) do
    kaspi_payment_link =
      normalize_blank(Map.get(attrs, "kaspi_payment_link") || Map.get(attrs, :kaspi_payment_link))

    payment_method =
      normalize_blank(Map.get(attrs, "payment_method") || Map.get(attrs, :payment_method)) ||
        if(kaspi_payment_link, do: "kaspi_link")

    invoice_or_id
    |> get_billing_invoice!()
    |> update_billing_invoice(%{
      payment_method: payment_method,
      kaspi_payment_link: kaspi_payment_link,
      due_at: parse_datetime(Map.get(attrs, "due_at") || Map.get(attrs, :due_at))
    })
  end

  @doc "Reactivates a suspended/past-due tenant without changing its current plan or period."
  def reactivate_subscription(subscription_or_id) do
    subscription_or_id
    |> get_subscription!()
    |> update_subscription(%{
      status: SubscriptionStatus.active(),
      grace_until: nil,
      blocked_reason: nil
    })
  end

  @doc "Extends a tenant grace period until the given datetime."
  def extend_grace_period(subscription_or_id, grace_until) do
    subscription_or_id
    |> get_subscription!()
    |> update_subscription(%{
      status: SubscriptionStatus.grace_period(),
      grace_until: grace_until,
      blocked_reason: nil
    })
  end

  defp admin_client_summary(company) do
    subscription =
      case get_current_subscription(company.id) do
        {:ok, subscription} -> subscription
        {:error, :not_found} -> nil
      end

    legacy_subscription =
      if subscription do
        nil
      else
        latest_legacy_subscription(company.id)
      end

    plan = tenant_snapshot_plan(subscription, legacy_subscription)

    used_documents =
      case current_document_usage(company.id) do
        {:ok, used} -> used
        _ -> legacy_document_usage(legacy_subscription)
      end

    document_limit = plan && plan.monthly_document_limit
    user_limit = plan && plan.included_users
    occupied_users = occupied_seat_count(company.id)

    overdue_invoices =
      BillingInvoice
      |> where([i], i.company_id == ^company.id and i.status == ^BillingInvoiceStatus.overdue())
      |> Repo.aggregate(:count, :id)

    %{
      company: company,
      subscription: subscription,
      plan: plan,
      subscription_status:
        (subscription && subscription.status) ||
          (legacy_subscription && legacy_subscription.status),
      occupied_users: occupied_users,
      user_limit: user_limit,
      used_documents: used_documents,
      document_limit: document_limit,
      period_end:
        (subscription && subscription.current_period_end) ||
          (legacy_subscription && legacy_subscription.period_end),
      overdue_invoices: overdue_invoices
    }
  end

  defp active_client_count do
    subscription_count(SubscriptionStatus.active()) + legacy_paid_client_count()
  end

  defp trial_client_count do
    subscription_count(SubscriptionStatus.trialing()) + legacy_trial_client_count()
  end

  defp subscription_count(status) do
    Subscription
    |> where([s], s.status == ^status)
    |> Repo.aggregate(:count, :id)
  end

  defp legacy_paid_client_count do
    legacy_subscriptions_without_current_billing_query()
    |> where([s], s.status == "active" and s.plan in ["starter", "basic"])
    |> Repo.aggregate(:count, :id)
  end

  defp legacy_trial_client_count do
    legacy_subscriptions_without_current_billing_query()
    |> where([s], s.status == "active" and s.plan == "trial")
    |> Repo.aggregate(:count, :id)
  end

  defp overdue_client_count do
    BillingInvoice
    |> where([i], i.status == ^BillingInvoiceStatus.overdue())
    |> select([i], count(fragment("DISTINCT ?", i.company_id)))
    |> Repo.one()
  end

  defp monthly_collected_revenue(month_start, now) do
    BillingInvoice
    |> where([i], i.status == ^BillingInvoiceStatus.paid())
    |> where([i], not is_nil(i.paid_at) and i.paid_at >= ^month_start and i.paid_at <= ^now)
    |> select([i], coalesce(sum(i.amount_kzt), 0))
    |> Repo.one()
  end

  defp upcoming_renewal_count(now, horizon) do
    billing_count =
      Subscription
      |> where([s], s.status == ^SubscriptionStatus.active())
      |> where([s], s.current_period_end > ^now and s.current_period_end <= ^horizon)
      |> Repo.aggregate(:count, :id)

    legacy_count =
      legacy_subscriptions_without_current_billing_query()
      |> where([s], s.status == "active" and s.period_end > ^now and s.period_end <= ^horizon)
      |> Repo.aggregate(:count, :id)

    billing_count + legacy_count
  end

  defp invoices_due_soon(now, horizon) do
    BillingInvoice
    |> where([i], i.status == ^BillingInvoiceStatus.sent())
    |> where([i], not is_nil(i.due_at) and i.due_at >= ^now and i.due_at <= ^horizon)
    |> order_by([i], asc: i.due_at)
    |> preload(:company)
    |> Repo.all()
  end

  defp unpaid_billing_invoices do
    BillingInvoice
    |> where([i], i.status in ^[BillingInvoiceStatus.sent(), BillingInvoiceStatus.overdue()])
    |> order_by([i], asc: i.due_at, desc: i.inserted_at)
    |> preload(:company)
    |> Repo.all()
  end

  defp legacy_pending_billing_invoice_summaries(nil) do
    legacy_subscriptions_without_current_billing_query()
    |> where([s], s.status == "active" and s.plan in ["starter", "basic"])
    |> join(:inner, [s], c in Company, on: c.id == s.company_id)
    |> order_by([s, _billing, c], asc: s.period_end, asc: c.name)
    |> select([s, _billing, c], {s, c})
    |> Repo.all()
    |> Enum.map(fn {subscription, company} ->
      plan = tenant_snapshot_plan(nil, subscription)

      %{
        id: "pending-#{subscription.id}",
        company: company,
        status: "pending_invoice",
        kaspi_payment_link: nil,
        due_at: subscription.period_end,
        payments: [],
        plan_snapshot_code: subscription.plan,
        amount_kzt: plan.price_kzt || 0,
        virtual?: true
      }
    end)
  end

  defp legacy_pending_billing_invoice_summaries("pending_invoice"),
    do: legacy_pending_billing_invoice_summaries(nil)

  defp legacy_pending_billing_invoice_summaries(_status), do: []

  defp legacy_subscriptions_without_current_billing_query do
    TenantSubscription
    |> join(:left, [legacy], billing in Subscription,
      on:
        billing.company_id == legacy.company_id and
          billing.status in ^@current_subscription_statuses
    )
    |> where([_legacy, billing], is_nil(billing.id))
  end

  defp legacy_document_usage(nil), do: 0

  defp legacy_document_usage(%TenantSubscription{} = subscription) do
    TenantUsageEvent
    |> where(
      [u],
      u.company_id == ^subscription.company_id and
        u.occurred_at >= ^subscription.period_start and
        u.occurred_at < ^subscription.period_end
    )
    |> Repo.aggregate(:count, :id)
  end

  defp recently_reactivated_clients(now) do
    since = DateTime.add(now, -30, :day)

    BillingAuditEvent
    |> where([e], e.action == "subscription_status_changed")
    |> where([e], fragment("?->>'to_status' = 'active'", e.metadata))
    |> where([e], e.inserted_at >= ^since)
    |> order_by([e], desc: e.inserted_at)
    |> preload(:company)
    |> limit(10)
    |> Repo.all()
  end

  defp send_renewal_reminders(now, days_until_due) do
    stage = Map.fetch!(@renewal_reminder_days, days_until_due)
    target_date = now |> DateTime.add(days_until_due, :day) |> DateTime.to_date()

    Subscription
    |> where([s], s.status == ^SubscriptionStatus.active())
    |> where([s], fragment("date(?)", s.current_period_end) == ^target_date)
    |> preload([:company, :plan, :next_plan])
    |> Repo.all()
    |> Enum.reduce([], fn subscription, sent ->
      if reminder_already_sent?("subscription", subscription.id, stage) do
        sent
      else
        deliver_customer_reminder(subscription.company, %{
          stage: Atom.to_string(stage),
          company_name: subscription.company.name,
          amount_kzt: subscription.plan.price_kzt,
          due_at: subscription.current_period_end
        })

        insert_reminder_event!(
          subscription.company_id,
          "subscription",
          subscription.id,
          stage,
          now,
          %{due_at: subscription.current_period_end, plan_code: subscription.plan.code}
        )

        [subscription | sent]
      end
    end)
    |> Enum.reverse()
  end

  defp send_overdue_invoice_reminders(now) do
    BillingInvoice
    |> where([i], i.status == ^BillingInvoiceStatus.overdue())
    |> preload(:company)
    |> Repo.all()
    |> Enum.reduce([], fn invoice, sent ->
      if reminder_already_sent?("billing_invoice", invoice.id, :overdue) do
        sent
      else
        deliver_customer_reminder(invoice.company, %{
          stage: "overdue",
          company_name: invoice.company.name,
          amount_kzt: invoice.amount_kzt,
          due_at: invoice.due_at,
          payment_link: invoice.kaspi_payment_link
        })

        insert_reminder_event!(
          invoice.company_id,
          "billing_invoice",
          invoice.id,
          :overdue,
          now,
          %{due_at: invoice.due_at, amount_kzt: invoice.amount_kzt}
        )

        [invoice | sent]
      end
    end)
    |> Enum.reverse()
  end

  defp send_suspended_subscription_notices(now) do
    Subscription
    |> where([s], s.status == ^SubscriptionStatus.suspended())
    |> preload([:company, :plan])
    |> Repo.all()
    |> Enum.reduce([], fn subscription, sent ->
      if reminder_already_sent?("subscription", subscription.id, :suspended) do
        sent
      else
        deliver_customer_reminder(subscription.company, %{
          stage: "suspended",
          company_name: subscription.company.name,
          amount_kzt: subscription.plan.price_kzt,
          due_at: subscription.grace_until || subscription.current_period_end
        })

        insert_reminder_event!(
          subscription.company_id,
          "subscription",
          subscription.id,
          :suspended,
          now,
          %{blocked_reason: subscription.blocked_reason}
        )

        [subscription | sent]
      end
    end)
    |> Enum.reverse()
  end

  defp send_high_value_overdue_alerts(now) do
    BillingInvoice
    |> where([i], i.status == ^BillingInvoiceStatus.overdue())
    |> where([i], i.plan_snapshot_code == "basic" or i.amount_kzt >= 29_900)
    |> preload(:company)
    |> Repo.all()
    |> Enum.reduce([], fn invoice, sent ->
      if reminder_already_sent?("billing_invoice", invoice.id, :admin_high_value_overdue) do
        sent
      else
        deliver_admin_alert(%{
          company_name: invoice.company.name,
          amount_kzt: invoice.amount_kzt,
          due_at: invoice.due_at
        })

        insert_reminder_event!(
          invoice.company_id,
          "billing_invoice",
          invoice.id,
          :admin_high_value_overdue,
          now,
          %{amount_kzt: invoice.amount_kzt, plan_code: invoice.plan_snapshot_code}
        )

        [invoice | sent]
      end
    end)
    |> Enum.reverse()
  end

  defp deliver_customer_reminder(%Company{} = company, attrs) do
    company
    |> billing_recipient_emails()
    |> Enum.each(&EmailSender.send_billing_reminder_email(&1, attrs))
  end

  defp deliver_admin_alert(attrs) do
    User
    |> where([u], u.is_platform_admin == true)
    |> select([u], u.email)
    |> Repo.all()
    |> Enum.uniq()
    |> Enum.each(&EmailSender.send_billing_admin_alert_email(&1, attrs))
  end

  defp billing_recipient_emails(%Company{} = company) do
    membership_emails =
      TenantMembership
      |> where([m], m.company_id == ^company.id)
      |> where([m], m.status == "active" and m.role in ["owner", "admin"])
      |> join(:inner, [m], u in User, on: u.id == m.user_id)
      |> select([_m, u], u.email)
      |> Repo.all()

    company_owner_email =
      company
      |> Repo.preload(:user)
      |> Map.get(:user)
      |> case do
        %User{email: email} -> [email]
        _ -> []
      end

    (membership_emails ++ company_owner_email)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp reminder_already_sent?(subject_type, subject_id, stage) do
    stage = Atom.to_string(stage)

    BillingAuditEvent
    |> where([e], e.action == "billing_reminder_sent")
    |> where([e], e.subject_type == ^subject_type and e.subject_id == ^subject_id)
    |> where([e], fragment("?->>'stage' = ?", e.metadata, ^stage))
    |> Repo.exists?()
  end

  defp insert_reminder_event!(company_id, subject_type, subject_id, stage, now, metadata) do
    %BillingAuditEvent{}
    |> BillingAuditEvent.changeset(%{
      company_id: company_id,
      action: "billing_reminder_sent",
      subject_type: subject_type,
      subject_id: subject_id,
      metadata:
        metadata
        |> stringify_metadata_values()
        |> Map.merge(%{
          stage: Atom.to_string(stage),
          sent_at: DateTime.to_iso8601(now),
          channel: "email",
          in_app: true
        })
    })
    |> Repo.insert!()
  end

  defp insert_audit_event!(company_id, actor_user_id, action, subject_type, subject_id, metadata) do
    %BillingAuditEvent{}
    |> BillingAuditEvent.changeset(%{
      company_id: company_id,
      actor_user_id: actor_user_id,
      action: action,
      subject_type: subject_type,
      subject_id: subject_id,
      metadata: stringify_metadata_values(metadata)
    })
    |> Repo.insert!()
  end

  defp maybe_insert_subscription_status_change!(old_subscription, new_subscription, metadata) do
    if old_subscription.status != new_subscription.status do
      insert_audit_event!(
        new_subscription.company_id,
        Map.get(metadata, :actor_user_id),
        "subscription_status_changed",
        "subscription",
        new_subscription.id,
        metadata
        |> Map.delete(:actor_user_id)
        |> Map.merge(%{
          from_status: old_subscription.status,
          to_status: new_subscription.status
        })
      )
    end
  end

  defp tenant_billing_reminders(subscription, outstanding_invoices) do
    invoice_reminders =
      outstanding_invoices
      |> Enum.filter(&(&1.status == BillingInvoiceStatus.overdue()))
      |> Enum.map(fn invoice ->
        %{
          kind: :overdue_payment,
          severity: :warning,
          invoice_id: invoice.id,
          message: "Billing invoice is overdue. Please pay it or submit payment proof."
        }
      end)

    subscription_reminders =
      case subscription do
        %Subscription{status: "suspended"} ->
          [
            %{
              kind: :subscription_suspended,
              severity: :danger,
              message: "Subscription is suspended until payment is confirmed."
            }
          ]

        _ ->
          []
      end

    invoice_reminders ++ subscription_reminders
  end

  defp stringify_metadata_values(metadata) do
    Map.new(metadata, fn
      {key, %DateTime{} = value} -> {key, DateTime.to_iso8601(value)}
      {key, value} -> {key, value}
    end)
  end

  defp maybe_filter_invoice_status(query, nil), do: query

  defp maybe_filter_invoice_status(query, status) do
    where(query, [i], i.status == ^status)
  end

  defp normalize_blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_blank(value), do: value

  defp parse_datetime(%DateTime{} = datetime), do: datetime
  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        nil

      String.length(value) == 10 ->
        case Date.from_iso8601(value) do
          {:ok, date} -> DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
          _ -> nil
        end

      true ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
          _ -> nil
        end
    end
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

  defp create_due_renewal_invoice(%Subscription{} = subscription) do
    period_start = subscription.current_period_end
    period_end = DateTime.add(period_start, 30, :day)

    existing =
      BillingInvoice
      |> where([i], i.subscription_id == ^subscription.id)
      |> where([i], i.period_start == ^period_start and i.period_end == ^period_end)
      |> where([i], i.note == "renewal")
      |> where([i], i.status != ^BillingInvoiceStatus.canceled())
      |> Repo.one()

    if existing do
      {:skipped, existing}
    else
      plan = subscription.next_plan || subscription.plan

      create_renewal_invoice(subscription, plan,
        period_start: period_start,
        period_end: period_end,
        due_at: subscription.current_period_end
      )
    end
  end

  defp maybe_move_to_overdue_grace(%Subscription{} = subscription, due_at) do
    if subscription.status in [SubscriptionStatus.active(), SubscriptionStatus.trialing()] do
      grace_until = DateTime.add(due_at, @overdue_grace_days, :day)
      {:ok, grace} = move_subscription_to_grace_period(subscription, grace_until)
      grace
    else
      nil
    end
  end

  defp maybe_collect_subscription(acc, _key, nil), do: acc

  defp maybe_collect_subscription(acc, key, subscription),
    do: update_in(acc[key], &[subscription | &1])

  defp reverse_lifecycle_result_lists(result) do
    Map.new(result, fn {key, value} ->
      if is_list(value), do: {key, Enum.reverse(value)}, else: {key, value}
    end)
  end

  defp ensure_plan_direction(current_plan, target_plan, direction) do
    current_rank = Map.get(@plan_rank, current_plan.code, -1)
    target_rank = Map.get(@plan_rank, target_plan.code, -1)

    case direction do
      :upgrade when target_rank > current_rank -> :ok
      :downgrade when target_rank < current_rank -> :ok
      :upgrade -> {:error, :not_an_upgrade}
      :downgrade -> {:error, :not_a_downgrade}
    end
  end

  defp ensure_target_plan_can_hold_current_seats(subscription, target_plan) do
    used = occupied_seat_count(subscription.company_id)
    target_limit = target_plan.included_users

    if used > target_limit do
      {:error, :seat_limit_reached,
       %{company_id: subscription.company_id, used: used, target_limit: target_limit}}
    else
      :ok
    end
  end

  defp ensure_target_plan_can_hold_current_usage(subscription, target_plan) do
    {:ok, used} = current_document_usage(subscription.company_id)
    target_limit = target_plan.monthly_document_limit

    if used > target_limit do
      {:error, :document_usage_exceeds_target,
       %{company_id: subscription.company_id, used: used, target_limit: target_limit}}
    else
      :ok
    end
  end

  defp update_subscription(subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
    |> preload_subscription_result()
    |> case do
      {:ok, updated_subscription} ->
        maybe_insert_subscription_status_change!(subscription, updated_subscription, %{
          source: "billing_update"
        })

        {:ok, updated_subscription}

      other ->
        other
    end
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

  defp ensure_subscription_allows_creation(%Subscription{} = subscription) do
    if SubscriptionStatus.good_standing?(subscription.status) do
      :ok
    else
      {:error, :subscription_restricted,
       %{
         company_id: subscription.company_id,
         plan: subscription.plan.code,
         status: subscription.status,
         blocked_reason: subscription.blocked_reason,
         period_end: subscription.current_period_end
       }}
    end
  end

  defp document_quota_details(subscription, used, limit, remaining) do
    %{
      company_id: subscription.company_id,
      plan: subscription.plan.code,
      status: subscription.status,
      used: used,
      limit: limit,
      remaining: remaining,
      period_end: subscription.current_period_end
    }
  end

  defp seat_quota_details(subscription, used, limit, remaining) do
    %{
      company_id: subscription.company_id,
      plan: subscription.plan.code,
      status: subscription.status,
      used: used,
      limit: limit,
      remaining: remaining
    }
  end

  defp occupied_seat_count(company_id) do
    TenantMembership
    |> where([m], m.company_id == ^company_id and m.status in ^@occupied_membership_statuses)
    |> Repo.aggregate(:count, :id)
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

  defp get_payment_for_update!(payment_or_id) do
    payment_id = record_id(payment_or_id)

    Payment
    |> where([p], p.id == ^payment_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

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
