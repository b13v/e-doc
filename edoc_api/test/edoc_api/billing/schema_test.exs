defmodule EdocApi.Billing.SchemaTest do
  use EdocApi.DataCase, async: false

  alias EdocApi.Billing

  alias EdocApi.Billing.{
    BillingAuditEvent,
    BillingInvoice,
    Payment,
    Plan,
    Subscription,
    UsageCounter,
    UsageEvent
  }

  alias EdocApi.TestFixtures

  describe "plans" do
    test "validates and normalizes plan codes" do
      changeset =
        Plan.changeset(%Plan{}, %{
          "code" => " Starter ",
          "name" => "Starter",
          "price_kzt" => 9900,
          "monthly_document_limit" => 50,
          "included_users" => 2,
          "is_active" => true
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :code) == "starter"
    end

    test "seeds trial starter and basic plans idempotently" do
      assert {:ok, %{count: 3}} = Billing.seed_default_plans()
      assert {:ok, %{count: 3}} = Billing.seed_default_plans()

      assert Repo.aggregate(Plan, :count, :id) == 3
      assert Repo.get_by!(Plan, code: "trial").monthly_document_limit == 10
      assert Repo.get_by!(Plan, code: "starter").included_users == 2
      assert Repo.get_by!(Plan, code: "basic").monthly_document_limit == 500
    end
  end

  describe "subscriptions" do
    test "does not expose subscription extra seats" do
      refute :extra_user_seats in Subscription.__schema__(:fields)
    end

    test "validates canonical status and tenant period" do
      company = create_company!()
      plan = create_plan!("starter")
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        Subscription.changeset(%Subscription{}, %{
          company_id: company.id,
          plan_id: plan.id,
          status: "active",
          current_period_start: now,
          current_period_end: DateTime.add(now, 30, :day),
          auto_renew_mode: "manual"
        })

      assert changeset.valid?

      invalid = Subscription.changeset(%Subscription{}, %{status: "unknown"})
      refute invalid.valid?
      assert "is invalid" in errors_on(invalid).status
    end
  end

  describe "billing invoices and payments" do
    test "validates billing invoice and payment status models" do
      company = create_company!()
      plan = create_plan!("basic")
      subscription = create_subscription!(company, plan)
      user = TestFixtures.create_user!()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      invoice_changeset =
        BillingInvoice.changeset(%BillingInvoice{}, %{
          company_id: company.id,
          subscription_id: subscription.id,
          period_start: now,
          period_end: DateTime.add(now, 30, :day),
          plan_snapshot_code: plan.code,
          amount_kzt: plan.price_kzt,
          status: "sent",
          payment_method: "kaspi_link",
          kaspi_payment_link: "https://pay.kaspi.kz/example",
          issued_at: now,
          due_at: DateTime.add(now, 3, :day),
          activated_by_user_id: user.id,
          note: "Renewal"
        })

      assert invoice_changeset.valid?
      invoice = Repo.insert!(invoice_changeset)

      payment_changeset =
        Payment.changeset(%Payment{}, %{
          company_id: company.id,
          billing_invoice_id: invoice.id,
          amount_kzt: invoice.amount_kzt,
          method: "kaspi_link",
          status: "pending_confirmation",
          paid_at: now,
          confirmed_by_user_id: user.id,
          external_reference: "kaspi-123",
          proof_attachment_url: "https://example.com/proof.png"
        })

      assert payment_changeset.valid?

      invalid = BillingInvoice.changeset(%BillingInvoice{}, %{status: "paid_by_cash"})
      refute invalid.valid?
      assert "is invalid" in errors_on(invalid).status

      invalid_link_method =
        BillingInvoice.changeset(%BillingInvoice{}, %{
          company_id: company.id,
          subscription_id: subscription.id,
          period_start: now,
          period_end: DateTime.add(now, 30, :day),
          plan_snapshot_code: plan.code,
          amount_kzt: plan.price_kzt,
          status: "sent",
          payment_method: "manual",
          kaspi_payment_link: "https://pay.kaspi.kz/example"
        })

      refute invalid_link_method.valid?

      assert "must be kaspi_link when Kaspi payment link is present" in errors_on(
               invalid_link_method
             ).payment_method
    end
  end

  describe "usage tracking and audit" do
    test "validates usage counters, usage events, and audit events" do
      company = create_company!()
      user = TestFixtures.create_user!()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      period_end = DateTime.add(now, 30, :day)
      resource_id = Ecto.UUID.generate()

      counter_changeset =
        UsageCounter.changeset(%UsageCounter{}, %{
          company_id: company.id,
          metric: "billable_documents",
          period_start: now,
          period_end: period_end,
          value: 2
        })

      assert counter_changeset.valid?

      event_changeset =
        UsageEvent.changeset(%UsageEvent{}, %{
          company_id: company.id,
          metric: "billable_documents",
          resource_type: "invoice",
          resource_id: resource_id,
          count: 1,
          period_start: now,
          period_end: period_end
        })

      assert event_changeset.valid?

      audit_changeset =
        BillingAuditEvent.changeset(%BillingAuditEvent{}, %{
          company_id: company.id,
          actor_user_id: user.id,
          action: "payment_confirmed",
          subject_type: "payment",
          subject_id: resource_id,
          metadata: %{"reference" => "kaspi-123"}
        })

      assert audit_changeset.valid?
    end
  end

  defp create_company! do
    user = TestFixtures.create_user!()
    TestFixtures.create_company!(user)
  end

  defp create_plan!(code) do
    Repo.insert!(
      Plan.changeset(%Plan{}, %{
        code: code,
        name: String.capitalize(code),
        price_kzt: 10_000,
        monthly_document_limit: 50,
        included_users: 2,
        is_active: true
      })
    )
  end

  defp create_subscription!(company, plan) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      Subscription.changeset(%Subscription{}, %{
        company_id: company.id,
        plan_id: plan.id,
        status: "active",
        current_period_start: now,
        current_period_end: DateTime.add(now, 30, :day),
        auto_renew_mode: "manual"
      })
    )
  end
end
