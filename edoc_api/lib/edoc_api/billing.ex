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

  alias EdocApi.Core.{Company, TenantMembership}
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

    with {:ok, subscription} <- get_current_subscription(company_or_id),
         {:ok, _quota} <- ensure_can_record_document_usage(company_or_id, count) do
      company_id = record_id(company_or_id)

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

  defp ensure_can_record_document_usage(company_or_id, count) do
    with {:ok, subscription} <- get_current_subscription(company_or_id),
         :ok <- ensure_subscription_allows_creation(subscription),
         {:ok, used} <- current_document_usage(company_or_id) do
      limit = subscription.plan.monthly_document_limit
      remaining = max(limit - used, 0)

      if used + count > limit do
        {:error, :quota_exceeded, document_quota_details(subscription, used, limit, remaining)}
      else
        {:ok, document_quota_details(subscription, used, limit, remaining)}
      end
    end
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
      limit = subscription.plan.included_users + subscription.extra_user_seats
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

  @doc "Creates a draft upgrade billing invoice."
  def create_upgrade_invoice(subscription_or_id, plan_or_code, opts \\ []) do
    create_billing_invoice(subscription_or_id, plan_or_code, "upgrade", opts)
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

  @doc "Lists client billing summaries for the internal backoffice."
  def list_admin_clients do
    Company
    |> order_by([c], asc: c.name)
    |> preload(:user)
    |> Repo.all()
    |> Enum.map(&admin_client_summary/1)
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
      |> where([m], m.company_id == ^company.id)
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

    Map.merge(summary, %{
      memberships: memberships,
      invoices: invoices,
      payments: payments,
      notes: notes
    })
  end

  @doc "Lists billing invoices for backoffice review, optionally filtered by status."
  def list_admin_billing_invoices(filters \\ %{}) do
    status = normalize_blank(Map.get(filters, "status") || Map.get(filters, :status))

    BillingInvoice
    |> maybe_filter_invoice_status(status)
    |> order_by([i], desc: i.inserted_at)
    |> preload([:company, :payments])
    |> Repo.all()
  end

  @doc "Returns tenant-facing billing data for the current company."
  def tenant_billing_snapshot(company_or_id) do
    company_id = record_id(company_or_id)

    subscription =
      case get_current_subscription(company_id) do
        {:ok, subscription} -> subscription
        {:error, :not_found} -> nil
      end

    outstanding_invoices =
      BillingInvoice
      |> where([i], i.company_id == ^company_id and i.status in ^["sent", "overdue"])
      |> order_by([i], asc: i.due_at, desc: i.inserted_at)
      |> preload(:payments)
      |> Repo.all()

    %{
      subscription: subscription,
      plan: subscription && subscription.plan,
      outstanding_invoices: outstanding_invoices,
      blocked?: subscription && subscription.status in ["past_due", "suspended", "canceled"],
      overdue?: Enum.any?(outstanding_invoices, &(&1.status == "overdue"))
    }
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

  @doc "Adds extra user seats to a subscription."
  def add_extra_user_seats(subscription_or_id, count) do
    subscription = get_subscription!(subscription_or_id)
    count = parse_integer(count, 0)

    subscription
    |> update_subscription(%{extra_user_seats: subscription.extra_user_seats + max(count, 0)})
  end

  defp admin_client_summary(company) do
    subscription =
      case get_current_subscription(company.id) do
        {:ok, subscription} -> subscription
        {:error, :not_found} -> nil
      end

    used_documents =
      case current_document_usage(company.id) do
        {:ok, used} -> used
        _ -> 0
      end

    document_limit = subscription && subscription.plan.monthly_document_limit
    user_limit = subscription && subscription.plan.included_users + subscription.extra_user_seats
    occupied_users = occupied_seat_count(company.id)

    overdue_invoices =
      BillingInvoice
      |> where([i], i.company_id == ^company.id and i.status == ^BillingInvoiceStatus.overdue())
      |> Repo.aggregate(:count, :id)

    %{
      company: company,
      subscription: subscription,
      plan: subscription && subscription.plan,
      subscription_status: subscription && subscription.status,
      occupied_users: occupied_users,
      user_limit: user_limit,
      used_documents: used_documents,
      document_limit: document_limit,
      period_end: subscription && subscription.current_period_end,
      overdue_invoices: overdue_invoices
    }
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

  defp parse_integer(value, _default) when is_integer(value), do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _} -> integer
      :error -> default
    end
  end

  defp parse_integer(_value, default), do: default

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
