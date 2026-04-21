defmodule EdocApi.ObanWorkers.BillingLifecycleWorkerTest do
  use EdocApi.DataCase, async: false

  alias EdocApi.Billing
  alias EdocApi.Billing.{BillingInvoice, Subscription}
  alias EdocApi.ObanWorkers.BillingLifecycleWorker
  alias EdocApi.Repo
  alias EdocApi.TestFixtures

  test "dispatches renewal invoice generation" do
    seed_plans!()
    company = create_company!()
    now = ~U[2026-04-20 08:00:00Z]
    {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)

    {:ok, _subscription} =
      Billing.activate_subscription(subscription, "basic",
        period_start: ~U[2026-04-01 08:00:00Z],
        period_end: ~U[2026-05-01 08:00:00Z]
      )

    job = %Oban.Job{
      args: %{
        "action" => "generate_renewal_invoices",
        "now" => "2026-04-24T08:00:00Z"
      }
    }

    assert BillingLifecycleWorker.perform(job) == :ok
    assert Repo.get_by!(BillingInvoice, note: "renewal").period_start == ~U[2026-05-01 08:00:00Z]
  end

  test "dispatches overdue and grace-expiry processing" do
    seed_plans!()
    company = create_company!()
    now = ~U[2026-04-20 08:00:00Z]
    {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)
    {:ok, subscription} = Billing.activate_subscription(subscription, "starter")
    {:ok, invoice} = Billing.create_renewal_invoice(subscription, "starter", due_at: now)
    {:ok, _invoice} = Billing.send_billing_invoice(invoice, payment_method: "manual", now: now)

    assert BillingLifecycleWorker.perform(%Oban.Job{
             args: %{"action" => "process_overdue_billing", "now" => "2026-04-21T08:00:00Z"}
           }) == :ok

    grace = Repo.get!(Subscription, subscription.id)
    assert grace.status == "grace_period"
    assert grace.grace_until == ~U[2026-04-27 08:00:00Z]

    assert BillingLifecycleWorker.perform(%Oban.Job{
             args: %{"action" => "process_grace_expirations", "now" => "2026-04-28T08:00:00Z"}
           }) == :ok

    suspended = Repo.get!(Subscription, subscription.id)
    assert suspended.status == "suspended"
    assert suspended.blocked_reason == "payment_overdue"
  end

  test "dispatches billing reminder processing" do
    seed_plans!()
    company = create_company!()
    now = ~U[2026-04-20 08:00:00Z]
    {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)

    {:ok, _subscription} =
      Billing.activate_subscription(subscription, "starter",
        period_start: ~U[2026-04-01 08:00:00Z],
        period_end: ~U[2026-04-27 08:00:00Z]
      )

    assert BillingLifecycleWorker.perform(%Oban.Job{
             args: %{"action" => "send_billing_reminders", "now" => "2026-04-20T08:00:00Z"}
           }) == :ok

    assert Repo.get_by!(EdocApi.Billing.BillingAuditEvent, action: "billing_reminder_sent")
  end

  defp seed_plans! do
    assert {:ok, %{count: 3}} = Billing.seed_default_plans()
  end

  defp create_company! do
    user = TestFixtures.create_user!()
    TestFixtures.create_company!(user)
  end
end
