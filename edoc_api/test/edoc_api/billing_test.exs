defmodule EdocApi.BillingTest do
  use ExUnit.Case, async: true

  alias EdocApi.Billing
  alias EdocApi.Billing.{BillingInvoiceStatus, PaymentStatus, SubscriptionStatus}

  describe "domain responsibilities" do
    test "lists the explicit billing context responsibilities" do
      assert Billing.responsibilities() == [
               :plans,
               :subscriptions,
               :billing_invoices,
               :payments,
               :usage_counters,
               :billing_audit_events
             ]
    end

    test "documents separate state models for subscriptions, invoices, payments, and usage" do
      assert Billing.state_models() == %{
               subscription: SubscriptionStatus.all(),
               billing_invoice: BillingInvoiceStatus.all(),
               payment: PaymentStatus.all(),
               usage_tracking: [:usage_events, :usage_counters]
             }
    end

    test "uses company_id as the tenant boundary for billing" do
      assert Billing.tenant_key() == :company_id
    end
  end

  describe "subscription statuses" do
    test "defines canonical subscription statuses" do
      assert SubscriptionStatus.all() == [
               "trialing",
               "active",
               "grace_period",
               "past_due",
               "suspended",
               "canceled"
             ]
    end

    test "classifies subscription good-standing states" do
      assert SubscriptionStatus.good_standing?("trialing")
      assert SubscriptionStatus.good_standing?("active")
      assert SubscriptionStatus.good_standing?("grace_period")

      refute SubscriptionStatus.good_standing?("past_due")
      refute SubscriptionStatus.good_standing?("suspended")
      refute SubscriptionStatus.good_standing?("canceled")
    end
  end

  describe "billing invoice statuses" do
    test "defines canonical billing invoice statuses" do
      assert BillingInvoiceStatus.all() == ["draft", "sent", "paid", "overdue", "canceled"]
    end

    test "classifies payable billing invoice states" do
      assert BillingInvoiceStatus.payable?("sent")
      assert BillingInvoiceStatus.payable?("overdue")

      refute BillingInvoiceStatus.payable?("draft")
      refute BillingInvoiceStatus.payable?("paid")
      refute BillingInvoiceStatus.payable?("canceled")
    end
  end

  describe "payment statuses" do
    test "defines canonical payment statuses" do
      assert PaymentStatus.all() == ["pending_confirmation", "confirmed", "rejected"]
    end

    test "classifies final payment states" do
      refute PaymentStatus.final?("pending_confirmation")
      assert PaymentStatus.final?("confirmed")
      assert PaymentStatus.final?("rejected")
    end
  end
end
