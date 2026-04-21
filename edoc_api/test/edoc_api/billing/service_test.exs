defmodule EdocApi.Billing.ServiceTest do
  use EdocApi.DataCase, async: false

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
  alias EdocApi.Core.TenantMembership

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

    test "does not record batched usage when count would exceed the document limit" do
      seed_plans!()
      company = create_company!()
      {:ok, _subscription} = Billing.create_trial_subscription(company.id)

      assert {:ok, _event} =
               Billing.record_document_usage(company.id, "invoice", Ecto.UUID.generate(),
                 count: 9
               )

      assert {:error, :quota_exceeded, %{used: 9, limit: 10, remaining: 1}} =
               Billing.record_document_usage(company.id, "act", Ecto.UUID.generate(), count: 2)

      assert Billing.current_document_usage(company.id) == {:ok, 9}
      assert Repo.aggregate(UsageEvent, :count, :id) == 1
    end
  end

  describe "document creation enforcement" do
    test "allows creation while usage is below quota and blocks when quota is reached" do
      seed_plans!()
      company = create_company!()
      now = ~U[2026-04-20 08:00:00Z]
      {:ok, _subscription} = Billing.create_trial_subscription(company.id, now: now)

      assert Billing.can_create_document?(company.id)

      assert {:ok, %{used: 0, limit: 10, remaining: 10, status: "trialing"}} =
               Billing.ensure_can_create_document(company.id)

      for index <- 1..10 do
        assert {:ok, _event} =
                 Billing.record_document_usage(company.id, "invoice", Ecto.UUID.generate(),
                   count: 1,
                   occurred_at: DateTime.add(now, index, :second)
                 )
      end

      refute Billing.can_create_document?(company.id)

      assert {:error, :quota_exceeded,
              %{used: 10, limit: 10, remaining: 0, plan: "trial", status: "trialing"}} =
               Billing.ensure_can_create_document(company.id)
    end

    test "blocks document creation for suspended and past-due tenants but allows grace period" do
      seed_plans!()
      company = create_company!()
      {:ok, subscription} = Billing.create_trial_subscription(company.id)

      assert {:ok, grace} =
               Billing.move_subscription_to_grace_period(
                 subscription,
                 DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)
               )

      assert Billing.can_create_document?(company.id)
      assert {:ok, %{status: "grace_period"}} = Billing.ensure_can_create_document(company.id)

      assert {:ok, suspended} = Billing.suspend_subscription(grace, "payment_overdue")

      refute Billing.can_create_document?(company.id)

      assert {:error, :subscription_restricted,
              %{status: "suspended", blocked_reason: "payment_overdue"}} =
               Billing.ensure_can_create_document(company.id)

      {:ok, past_due} =
        suspended
        |> Subscription.changeset(%{status: "past_due", blocked_reason: "payment_past_due"})
        |> Repo.update()

      refute Billing.can_create_document?(company.id)

      assert {:error, :subscription_restricted,
              %{status: "past_due", blocked_reason: "payment_past_due"}} =
               Billing.ensure_can_create_document(past_due.company_id)
    end
  end

  describe "seat enforcement" do
    test "counts active invited and pending memberships against included seats" do
      seed_plans!()
      company = create_company!()
      {:ok, subscription} = Billing.create_trial_subscription(company.id)

      assert Billing.can_add_user?(company.id)

      create_membership!(company.id, %{invite_email: "first@example.com", status: "invited"})

      refute Billing.can_add_user?(company.id)

      assert {:error, :seat_limit_reached, %{used: 2, limit: 2, plan: "trial"}} =
               Billing.ensure_can_add_user(company.id)

      {:ok, _subscription} = Billing.activate_subscription(subscription, "basic")

      assert Billing.can_add_user?(company.id)
      assert {:ok, %{used: 2, limit: 5, remaining: 3}} = Billing.ensure_can_add_user(company.id)

      create_membership!(company.id, %{
        invite_email: "pending@example.com",
        status: "pending_seat"
      })

      assert {:ok, %{used: 3, limit: 5, remaining: 2}} = Billing.ensure_can_add_user(company.id)
    end

    test "respects extra user seats" do
      seed_plans!()
      company = create_company!()
      {:ok, subscription} = Billing.create_trial_subscription(company.id)

      assert {:ok, _subscription} =
               subscription
               |> Subscription.changeset(%{extra_user_seats: 1})
               |> Repo.update()

      create_membership!(company.id, %{invite_email: "first@example.com", status: "invited"})

      assert {:ok, %{used: 2, limit: 3, remaining: 1}} = Billing.ensure_can_add_user(company.id)
    end
  end

  describe "billing invoices and payments" do
    test "attaches a normalized Kaspi link and records customer payment review metadata" do
      seed_plans!()
      company = create_company!()
      now = ~U[2026-04-20 08:00:00Z]
      {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)
      {:ok, invoice} = Billing.create_renewal_invoice(subscription, "basic", due_at: now)

      assert {:ok, linked_invoice} =
               Billing.attach_kaspi_payment_link(invoice, " https://pay.kaspi.kz/invoice-1 ")

      assert linked_invoice.payment_method == "kaspi_link"
      assert linked_invoice.kaspi_payment_link == "https://pay.kaspi.kz/invoice-1"

      assert {:ok, payment} =
               Billing.create_customer_payment_review(linked_invoice, %{
                 "external_reference" => "KASPI-REF-123",
                 "proof_attachment_url" => "https://example.com/proof.png",
                 "note" => "Paid from company account"
               })

      assert payment.method == "kaspi_link"
      assert payment.status == "pending_confirmation"
      assert payment.external_reference == "KASPI-REF-123"
      assert payment.proof_attachment_url == "https://example.com/proof.png"

      assert [note] = Billing.list_payment_review_notes(payment.id)
      assert note.metadata["note"] == "Paid from company account"
      assert note.subject_type == "payment"
      assert note.subject_id == payment.id
    end

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

    test "paid immediate upgrade invoice moves tenant to higher plan without extending the cycle" do
      seed_plans!()
      company = create_company!()
      admin = TestFixtures.create_user!()
      now = ~U[2026-04-20 08:00:00Z]
      {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)

      {:ok, subscription} =
        Billing.activate_subscription(subscription, "starter",
          period_start: ~U[2026-04-01 08:00:00Z],
          period_end: ~U[2026-05-01 08:00:00Z]
        )

      assert {:ok, invoice} =
               Billing.create_immediate_upgrade_invoice(subscription, "basic",
                 now: ~U[2026-04-20 08:00:00Z],
                 due_at: ~U[2026-04-22 08:00:00Z]
               )

      assert invoice.note == "upgrade"
      assert invoice.period_start == ~U[2026-04-20 08:00:00Z]
      assert invoice.period_end == ~U[2026-05-01 08:00:00Z]
      assert invoice.amount_kzt == 29_900

      {:ok, invoice} = Billing.send_billing_invoice(invoice, payment_method: "manual", now: now)
      {:ok, payment} = Billing.create_payment(invoice, method: "manual")

      assert {:ok, %{subscription: upgraded}} =
               Billing.confirm_manual_payment(payment, admin.id, now: ~U[2026-04-20 10:00:00Z])

      assert upgraded.plan.code == "basic"
      assert upgraded.current_period_start == ~U[2026-04-20 08:00:00Z]
      assert upgraded.current_period_end == ~U[2026-05-01 08:00:00Z]
      assert Billing.allowed_user_limit(company.id) == {:ok, 5}
    end

    test "scheduled downgrade is blocked when current seats or usage exceed target plan limits" do
      seed_plans!()
      company = create_company!()
      {:ok, subscription} = Billing.create_trial_subscription(company.id)
      {:ok, subscription} = Billing.activate_subscription(subscription, "basic")

      create_membership!(company.id, %{invite_email: "first@example.com", status: "invited"})
      create_membership!(company.id, %{invite_email: "second@example.com", status: "invited"})

      assert {:error, :seat_limit_reached, %{used: 3, target_limit: 2}} =
               Billing.schedule_downgrade(subscription, "starter", ~U[2026-05-20 08:00:00Z])

      Repo.delete_all(
        from(m in TenantMembership,
          where: m.company_id == ^company.id and not is_nil(m.invite_email)
        )
      )

      assert {:ok, _event} =
               Billing.record_document_usage(company.id, "invoice", Ecto.UUID.generate(),
                 count: 51
               )

      assert {:error, :document_usage_exceeds_target, %{used: 51, target_limit: 50}} =
               Billing.schedule_downgrade(subscription, "starter", ~U[2026-05-20 08:00:00Z])
    end

    test "scheduled downgrade renewal applies target plan and clears pending change on payment" do
      seed_plans!()
      company = create_company!()
      admin = TestFixtures.create_user!()
      {:ok, subscription} = Billing.create_trial_subscription(company.id)

      {:ok, subscription} =
        Billing.activate_subscription(subscription, "basic",
          period_start: ~U[2026-04-01 08:00:00Z],
          period_end: ~U[2026-05-01 08:00:00Z]
        )

      {:ok, scheduled} =
        Billing.schedule_downgrade(subscription, "starter", ~U[2026-05-01 08:00:00Z])

      assert scheduled.next_plan.code == "starter"

      assert %{created: [renewal]} =
               Billing.generate_renewal_invoices(now: ~U[2026-04-25 08:00:00Z])

      assert renewal.plan_snapshot_code == "starter"

      {:ok, renewal} = Billing.send_billing_invoice(renewal, payment_method: "manual")
      {:ok, payment} = Billing.create_payment(renewal, method: "manual")

      assert {:ok, %{subscription: downgraded}} =
               Billing.confirm_manual_payment(payment, admin.id, now: ~U[2026-04-26 08:00:00Z])

      assert downgraded.plan.code == "starter"
      assert downgraded.next_plan_id == nil
      assert downgraded.change_effective_at == nil
    end

    test "extra seats can be increased and decreased without dropping below occupied seats" do
      seed_plans!()
      company = create_company!()
      {:ok, subscription} = Billing.create_trial_subscription(company.id)

      assert {:ok, with_seats} = Billing.change_extra_user_seats(subscription, 3)
      assert with_seats.extra_user_seats == 3
      assert Billing.allowed_user_limit(company.id) == {:ok, 5}

      create_membership!(company.id, %{invite_email: "first@example.com", status: "invited"})
      create_membership!(company.id, %{invite_email: "second@example.com", status: "invited"})
      create_membership!(company.id, %{invite_email: "third@example.com", status: "invited"})

      assert {:error, :seat_limit_reached, %{used: 4, target_limit: 3}} =
               Billing.change_extra_user_seats(with_seats, 1)

      assert {:ok, reduced} = Billing.change_extra_user_seats(with_seats, 2)
      assert reduced.extra_user_seats == 2
      assert Billing.allowed_user_limit(company.id) == {:ok, 4}
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

    test "generates one renewal invoice per subscription period within the lead window" do
      seed_plans!()
      company = create_company!()
      now = ~U[2026-04-20 08:00:00Z]
      {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)

      {:ok, subscription} =
        Billing.activate_subscription(subscription, "basic",
          period_start: ~U[2026-04-01 08:00:00Z],
          period_end: ~U[2026-05-01 08:00:00Z]
        )

      assert %{created: [invoice], skipped: []} =
               Billing.generate_renewal_invoices(now: ~U[2026-04-24 08:00:00Z])

      assert invoice.subscription_id == subscription.id
      assert invoice.company_id == company.id
      assert invoice.note == "renewal"
      assert invoice.plan_snapshot_code == "basic"
      assert invoice.period_start == ~U[2026-05-01 08:00:00Z]
      assert invoice.period_end == ~U[2026-05-31 08:00:00Z]
      assert invoice.due_at == ~U[2026-05-01 08:00:00Z]

      assert %{created: [], skipped: [^invoice]} =
               Billing.generate_renewal_invoices(now: ~U[2026-04-25 08:00:00Z])

      assert Repo.aggregate(BillingInvoice, :count, :id) == 1
    end

    test "marks overdue billing invoices, moves tenants into grace, and suspends after grace" do
      seed_plans!()
      company = create_company!()
      now = ~U[2026-04-20 08:00:00Z]
      {:ok, subscription} = Billing.create_trial_subscription(company.id, now: now)

      {:ok, subscription} =
        Billing.activate_subscription(subscription, "starter",
          period_start: ~U[2026-04-01 08:00:00Z],
          period_end: ~U[2026-05-01 08:00:00Z]
        )

      {:ok, invoice} =
        Billing.create_renewal_invoice(subscription, "starter",
          period_start: ~U[2026-05-01 08:00:00Z],
          period_end: ~U[2026-05-31 08:00:00Z],
          due_at: ~U[2026-04-23 08:00:00Z]
        )

      {:ok, invoice} = Billing.send_billing_invoice(invoice, payment_method: "manual", now: now)

      assert %{overdue_invoices: [overdue_invoice], graced_subscriptions: [grace]} =
               Billing.process_overdue_billing(now: ~U[2026-04-24 08:00:00Z])

      assert overdue_invoice.id == invoice.id
      assert overdue_invoice.status == "overdue"
      assert grace.id == subscription.id
      assert grace.status == "grace_period"
      assert grace.grace_until == ~U[2026-04-30 08:00:00Z]
      assert grace.blocked_reason == nil
      assert Billing.can_create_document?(company.id)

      assert %{suspended_subscriptions: []} =
               Billing.process_grace_expirations(now: ~U[2026-04-29 08:00:00Z])

      assert %{suspended_subscriptions: [suspended]} =
               Billing.process_grace_expirations(now: ~U[2026-05-01 08:00:00Z])

      assert suspended.id == subscription.id
      assert suspended.status == "suspended"
      assert suspended.blocked_reason == "payment_overdue"
      refute Billing.can_create_document?(company.id)
    end
  end

  defp seed_plans! do
    assert {:ok, %{count: 3}} = Billing.seed_default_plans()
  end

  defp create_company! do
    user = TestFixtures.create_user!()
    TestFixtures.create_company!(user)
  end

  defp create_membership!(company_id, attrs) do
    attrs =
      Map.merge(
        %{company_id: company_id, role: "member"},
        attrs
      )

    %TenantMembership{}
    |> TenantMembership.changeset(attrs)
    |> Repo.insert!()
  end
end
