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
      assert Repo.get_by!(Plan, code: "starter").price_kzt == 2_900
      assert Repo.get_by!(Plan, code: "basic").monthly_document_limit == 500
      assert Repo.get_by!(Plan, code: "basic").price_kzt == 5_900
    end

    test "corrects persisted starter/basic prices and draft invoice amounts without rewriting sent invoices" do
      starter = create_plan!("starter", %{price_kzt: 9_900})
      basic = create_plan!("basic", %{price_kzt: 29_900, included_users: 5, monthly_document_limit: 500})
      company = create_company!()
      subscription = create_subscription!(company, starter)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      draft_starter =
        insert_billing_invoice!(subscription, %{
          plan_snapshot_code: "starter",
          amount_kzt: 9_900,
          status: "draft",
          period_start: now,
          period_end: DateTime.add(now, 30, :day)
        })

      draft_basic =
        insert_billing_invoice!(subscription, %{
          plan_snapshot_code: "basic",
          amount_kzt: 29_900,
          status: "draft",
          period_start: DateTime.add(now, 31, :day),
          period_end: DateTime.add(now, 61, :day)
        })

      sent_basic =
        insert_billing_invoice!(subscription, %{
          plan_snapshot_code: "basic",
          amount_kzt: 29_900,
          status: "sent",
          period_start: DateTime.add(now, 62, :day),
          period_end: DateTime.add(now, 92, :day),
          due_at: DateTime.add(now, 65, :day)
        })

      run_price_correction_queries!()

      assert Repo.get!(Plan, starter.id).price_kzt == 2_900
      assert Repo.get!(Plan, basic.id).price_kzt == 5_900
      assert Repo.get!(BillingInvoice, draft_starter.id).amount_kzt == 2_900
      assert Repo.get!(BillingInvoice, draft_basic.id).amount_kzt == 5_900
      assert Repo.get!(BillingInvoice, sent_basic.id).amount_kzt == 29_900
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

  defp create_plan!(code, overrides \\ %{}) do
    Repo.insert!(
      Plan.changeset(%Plan{}, %{
        code: code,
        name: String.capitalize(code),
        price_kzt: 10_000,
        monthly_document_limit: 50,
        included_users: 2,
        is_active: true
      } |> Map.merge(overrides))
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

  defp insert_billing_invoice!(subscription, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      BillingInvoice.changeset(%BillingInvoice{}, %{
        company_id: subscription.company_id,
        subscription_id: subscription.id,
        period_start: DateTime.add(now, 1, :day),
        period_end: DateTime.add(now, 31, :day),
        plan_snapshot_code: subscription.plan_id,
        amount_kzt: 10_000,
        status: "draft",
        due_at: nil,
        note: "renewal"
      } |> Map.merge(attrs))
    )
  end

  defp run_price_correction_queries! do
    Repo.query!("UPDATE plans SET price_kzt = 2900, updated_at = NOW() WHERE code = 'starter'")
    Repo.query!("UPDATE plans SET price_kzt = 5900, updated_at = NOW() WHERE code = 'basic'")

    Repo.query!(
      "UPDATE billing_invoices SET amount_kzt = 2900, updated_at = NOW() WHERE status = 'draft' AND plan_snapshot_code = 'starter'"
    )

    Repo.query!(
      "UPDATE billing_invoices SET amount_kzt = 5900, updated_at = NOW() WHERE status = 'draft' AND plan_snapshot_code = 'basic'"
    )
  end
end
