defmodule EdocApi.Billing.EnforcementIntegrationTest do
  use EdocApi.DataCase, async: false

  alias EdocApi.Billing
  alias EdocApi.Core
  alias EdocApi.Core.TenantUsageEvent
  alias EdocApi.Invoicing
  alias EdocApi.Repo
  alias EdocApi.TestFixtures

  describe "legacy document entry points with billing subscriptions" do
    test "draft creation is blocked by new billing quota before old monetization fallback" do
      seed_plans!()
      user = TestFixtures.create_user!()
      company = TestFixtures.create_company!(user)
      TestFixtures.create_company_bank_account!(company)
      {:ok, _subscription} = Billing.create_trial_subscription(company.id)

      for _ <- 1..10 do
        assert {:ok, _event} =
                 Billing.record_document_usage(company.id, "invoice", Ecto.UUID.generate())
      end

      assert {:error, :business_rule,
              %{
                rule: :quota_exceeded,
                details: %{used: 10, limit: 10, plan: "trial", status: "trialing"}
              }} =
               Invoicing.create_invoice_for_user(user.id, company.id, invoice_attrs())
    end

    test "issuing a contract records usage in new billing counters not legacy usage events" do
      seed_plans!()
      user = TestFixtures.create_user!()
      company = TestFixtures.create_company!(user)
      {:ok, _subscription} = Billing.create_trial_subscription(company.id)

      assert {:ok, contract} =
               Core.create_contract_for_user(user.id, contract_attrs(), [
                 %{"name" => "Service", "qty" => "1", "unit_price" => "1000"}
               ])

      assert {:ok, issued} = Core.issue_contract_for_user(user.id, contract.id)
      assert issued.status == "issued"
      assert Billing.current_document_usage(company.id) == {:ok, 1}
      assert Repo.aggregate(TenantUsageEvent, :count, :id) == 0
    end

    test "compatibility monetization facade records usage in billing not legacy usage events" do
      user = TestFixtures.create_user!()
      company = TestFixtures.create_company!(user)

      assert {:ok, %{used: 1, limit: 10, remaining: 9}} =
               EdocApi.Monetization.consume_document_quota(
                 company.id,
                 "invoice",
                 Ecto.UUID.generate(),
                 "invoice_issued"
               )

      assert Repo.aggregate(TenantUsageEvent, :count, :id) == 0
      assert {:ok, _subscription} = Billing.get_current_subscription(company.id)
      assert Billing.current_document_usage(company.id) == {:ok, 1}
    end
  end

  defp seed_plans! do
    assert {:ok, %{count: 3}} = Billing.seed_default_plans()
  end

  defp invoice_attrs do
    %{
      "service_name" => "Consulting",
      "issue_date" => Date.utc_today(),
      "currency" => "KZT",
      "buyer_name" => "Buyer LLC",
      "buyer_bin_iin" => "060215385673",
      "buyer_address" => "Buyer Address",
      "vat_rate" => 0,
      "items" => [
        %{"name" => "Service", "qty" => 1, "unit_price" => "100.00"}
      ]
    }
  end

  defp contract_attrs do
    %{
      "number" => "C-#{System.unique_integer([:positive])}",
      "issue_date" => Date.utc_today(),
      "buyer_name" => "Buyer LLC",
      "buyer_bin_iin" => "060215385673",
      "buyer_address" => "Buyer Address"
    }
  end
end
