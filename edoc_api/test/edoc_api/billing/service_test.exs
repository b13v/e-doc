defmodule EdocApi.Billing.ServiceTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Billing

  alias EdocApi.Billing.{
    BillingInvoice,
    Payment,
    Plan,
    Subscription,
    UsageCounter,
    UsageEvent
  }

  alias EdocApi.Repo
  alias EdocApi.TestFixtures

  describe "plans" do
    test "looks up active plans by code and lists active plans in canonical order" do
      seed_plans!()

      Repo.get_by!(Plan, code: "basic")
      |> Plan.changeset(%{is_active: false})
      |> Repo.update!()

      assert {:ok, trial} = Billing.get_plan_by_code(" trial ")
      assert trial.code == "trial"

      assert Billing.get_plan_by_code("basic") == {:error, :not_found}
      assert Enum.map(Billing.list_active_plans(), & &1.code) == ["trial", "starter"]
    end
  end

  describe "subscriptions" do
    test "creates a trial subscription for a new tenant and returns it as current subscription" do
      seed_plans!()
      company = create_company!()
      now = ~U[2026-04-20 08:00:00Z]

      assert {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)

      assert subscription.status == "trialing"
      assert subscription.current_period_start == now
      assert subscription.current_period_end == ~U[2026-05-04 08:00:00Z]
      assert subscription.plan.code == "trial"

      assert {:ok, current} = Billing.get_current_subscription(company.id)
      assert current.id == subscription.id
      assert current.plan.code == "trial"
    end

    test "transitions subscription through grace, suspension, reactivation, renewal, and plan change scheduling" do
      seed_plans!()
      company = create_company!()
      now = ~U[2026-04-20 08:00:00Z]
      {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)

      assert {:ok, grace} =
               Billing.move_subscription_to_grace_period(subscription, ~U[2026-05-07 08:00:00Z])

      assert grace.status == "grace_period"
      assert grace.grace_until == ~U[2026-05-07 08:00:00Z]

      assert {:ok, suspended} = Billing.suspend_subscription(grace, "payment_overdue")
      assert suspended.status == "suspended"
      assert suspended.blocked_reason == "payment_overdue"

      assert {:ok, starter} = Billing.get_plan_by_code("starter")
      assert {:ok, active} = Billing.activate_subscription(suspended, starter, now: now)
      assert active.status == "active"
      assert active.plan_id == starter.id
      assert active.blocked_reason == nil

      assert {:ok, renewed} =
               Billing.renew_subscription(active,
                 period_start: ~U[2026-05-20 08:00:00Z],
                 period_end: ~U[2026-06-20 08:00:00Z]
               )

      assert renewed.current_period_start == ~U[2026-05-20 08:00:00Z]
      assert renewed.current_period_end == ~U[2026-06-20 08:00:00Z]

      assert {:ok, scheduled} =
               Billing.schedule_plan_change(renewed, "basic", ~U[2026-06-20 08:00:00Z])

      assert scheduled.next_plan.code == "basic"
      assert scheduled.change_effective_at == ~U[2026-06-20 08:00:00Z]
    end
  end

  describe "usage" do
    test "reports plan limits and records document usage with an upserted counter" do
      seed_plans!()
      company = create_company!()
      now = ~U[2026-04-20 08:00:00Z]
      {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)

      assert Billing.allowed_document_limit(company.id) == {:ok, 10}
      assert Billing.allowed_user_limit(company.id) == {:ok, 2}
      assert Billing.current_document_usage(company.id) == {:ok, 0}

      invoice_id = Ecto.UUID.generate()
      act_id = Ecto.UUID.generate()

      assert {:ok, event} =
               Billing.record_document_usage(company.id, "invoice", invoice_id, count: 1)

      assert event.resource_type == "invoice"
      assert Billing.current_document_usage(company.id) == {:ok, 1}

      assert {:ok, _event} = Billing.record_document_usage(company.id, "act", act_id, count: 2)
      assert Billing.current_document_usage(company.id) == {:ok, 3}

      counter = Repo.get_by!(UsageCounter, company_id: company.id, metric: "billable_documents")
      assert counter.value == 3
      assert counter.period_start == subscription.current_period_start
      assert counter.period_end == subscription.current_period_end
      assert Repo.aggregate(UsageEvent, :count, :id) == 2
    end
  end

  describe "billing invoices and payments" do
    test "creates renewal and upgrade invoices, sends them, and marks overdue invoices" do
      seed_plans!()
      company = create_company!()
      now = ~U[2026-04-20 08:00:00Z]
      {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)

      assert {:ok, renewal} =
               Billing.create_renewal_invoice(subscription, "starter",
                 period_start: ~U[2026-05-04 08:00:00Z],
                 period_end: ~U[2026-06-04 08:00:00Z],
                 due_at: ~U[2026-04-23 08:00:00Z]
               )

      assert renewal.status == "draft"
      assert renewal.plan_snapshot_code == "starter"
      assert renewal.amount_kzt == 9_900

      assert {:ok, sent} =
               Billing.send_billing_invoice(renewal,
                 payment_method: "kaspi_link",
                 kaspi_payment_link: "https://pay.kaspi.kz/example",
                 now: now
               )

      assert sent.status == "sent"
      assert sent.issued_at == now

      assert {:ok, overdue} =
               Billing.mark_billing_invoice_overdue(sent, now: ~U[2026-04-24 08:00:00Z])

      assert overdue.status == "overdue"

      assert {:ok, upgrade} = Billing.create_upgrade_invoice(subscription, "basic", due_at: now)
      assert upgrade.note == "upgrade"
      assert upgrade.amount_kzt == 29_900
    end

    test "confirms manual payment atomically and is idempotent on repeated confirmation" do
      seed_plans!()
      company = create_company!()
      admin = TestFixtures.create_user!()
      now = ~U[2026-04-20 08:00:00Z]
      {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)

      {:ok, invoice} =
        Billing.create_renewal_invoice(subscription, "starter",
          period_start: ~U[2026-05-04 08:00:00Z],
          period_end: ~U[2026-06-04 08:00:00Z],
          due_at: ~U[2026-04-23 08:00:00Z]
        )

      {:ok, invoice} = Billing.send_billing_invoice(invoice, payment_method: "manual", now: now)

      assert {:ok, payment} =
               Billing.create_payment(invoice,
                 method: "manual",
                 paid_at: ~U[2026-04-20 09:00:00Z],
                 external_reference: "manual-123"
               )

      assert {:ok, %{payment: confirmed, invoice: paid_invoice, subscription: active}} =
               Billing.confirm_manual_payment(payment, admin.id, now: ~U[2026-04-20 10:00:00Z])

      assert confirmed.status == "confirmed"
      assert confirmed.confirmed_by_user_id == admin.id
      assert paid_invoice.status == "paid"
      assert paid_invoice.paid_at == ~U[2026-04-20 10:00:00Z]
      assert active.status == "active"
      assert active.current_period_start == invoice.period_start
      assert active.current_period_end == invoice.period_end

      assert {:ok,
              %{payment: same_payment, invoice: same_invoice, subscription: same_subscription}} =
               Billing.confirm_manual_payment(payment.id, admin.id, now: ~U[2026-04-20 11:00:00Z])

      assert same_payment.id == confirmed.id
      assert same_payment.confirmed_at == confirmed.confirmed_at
      assert same_invoice.paid_at == paid_invoice.paid_at
      assert same_subscription.current_period_end == active.current_period_end
      assert Repo.aggregate(Payment, :count, :id) == 1
    end

    test "rejects a pending payment without activating the subscription" do
      seed_plans!()
      company = create_company!()
      admin = TestFixtures.create_user!()
      now = ~U[2026-04-20 08:00:00Z]
      {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)
      {:ok, invoice} = Billing.create_upgrade_invoice(subscription, "basic", due_at: now)
      {:ok, invoice} = Billing.send_billing_invoice(invoice, payment_method: "manual", now: now)
      {:ok, payment} = Billing.create_payment(invoice, method: "manual")

      assert {:ok, rejected} =
               Billing.reject_payment(payment, admin.id, now: ~U[2026-04-20 10:00:00Z])

      assert rejected.status == "rejected"
      assert rejected.confirmed_by_user_id == admin.id
      assert Repo.get!(BillingInvoice, invoice.id).status == "sent"
      assert Repo.get!(Subscription, subscription.id).status == "trialing"
    end
  end

  defp seed_plans! do
    assert {:ok, %{count: 3}} = Billing.seed_default_plans()
  end

  defp create_company! do
    user = TestFixtures.create_user!()
    TestFixtures.create_company!(user)
  end
end
