defmodule EdocApi.Invoicing.InvoiceIssuanceTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Billing
  alias EdocApi.Invoicing
  import EdocApi.TestFixtures

  describe "issue_invoice_for_user/2" do
    test "issues a draft invoice with items and positive total" do
      user = create_user!()
      company = create_company!(user)
      create_company_bank_account!(company)
      invoice = create_invoice_with_items!(user, company)

      assert invoice.status == "draft"
      assert {:ok, issued} = Invoicing.issue_invoice_for_user(user.id, invoice.id)
      assert issued.status == "issued"
    end

    test "rejects already issued invoices" do
      user = create_user!()
      company = create_company!(user)
      invoice = insert_invoice!(user, company, %{status: "issued"})

      assert {:error, :business_rule,
              %{
                rule: :business_rule,
                details: %{
                  rule: :already_issued,
                  details: %{status: _, invoice_id: _}
                }
              }} =
               Invoicing.issue_invoice_for_user(user.id, invoice.id)
    end

    test "rejects non-draft status" do
      user = create_user!()
      company = create_company!(user)
      invoice = insert_invoice!(user, company, %{status: "paid"})

      assert {:error, :business_rule,
              %{
                rule: :business_rule,
                details: %{
                  rule: :cannot_issue,
                  details: %{status: "must be draft to issue", invoice_id: _}
                }
              }} =
               Invoicing.issue_invoice_for_user(user.id, invoice.id)
    end

    test "rejects invoices without items" do
      user = create_user!()
      company = create_company!(user)
      invoice = insert_invoice!(user, company, %{total: Decimal.new("100.00")})

      assert {:error, :business_rule,
              %{
                rule: :business_rule,
                details: %{
                  rule: :cannot_issue,
                  details: %{items: "must have at least 1 item", invoice_id: _}
                }
              }} =
               Invoicing.issue_invoice_for_user(user.id, invoice.id)
    end

    test "rejects non-positive totals" do
      user = create_user!()
      company = create_company!(user)

      invoice =
        insert_invoice!(user, company, %{
          total: Decimal.new("0.00"),
          subtotal: Decimal.new("0.00")
        })

      insert_item!(invoice)

      assert {:error, :business_rule,
              %{
                rule: :business_rule,
                details: %{
                  rule: :cannot_issue,
                  details: %{total: "must be > 0", invoice_id: _}
                }
              }} =
               Invoicing.issue_invoice_for_user(user.id, invoice.id)
    end

    test "rejects unknown invoice id" do
      user = create_user!()

      assert {:error, :not_found, %{resource: :invoice}} =
               Invoicing.issue_invoice_for_user(user.id, Ecto.UUID.generate())
    end

    test "rejects issuing a contract-linked invoice while the contract is only issued" do
      user = create_user!()
      company = create_company!(user)
      create_company_bank_account!(company)
      contract = create_contract!(company, %{"status" => "issued"})

      invoice =
        create_invoice_with_items!(user, company, %{
          "contract_id" => contract.id
        })

      assert {:error, :business_rule,
              %{
                rule: :business_rule,
                details: %{
                  rule: :contract_must_be_signed_to_issue_invoice,
                  details: %{
                    invoice_id: invoice_id,
                    contract_id: contract_id,
                    contract_status: "issued"
                  }
                }
              }} =
               Invoicing.issue_invoice_for_user(user.id, invoice.id)

      assert invoice_id == invoice.id
      assert contract_id == contract.id
    end

    test "allows issuing a contract-linked invoice when the contract is signed" do
      user = create_user!()
      company = create_company!(user)
      create_company_bank_account!(company)
      contract = create_contract!(company, %{"status" => "signed"})

      invoice =
        create_invoice_with_items!(user, company, %{
          "contract_id" => contract.id
        })

      assert {:ok, issued} = Invoicing.issue_invoice_for_user(user.id, invoice.id)
      assert issued.status == "issued"
    end

    test "rejects issuing when monthly document quota is exceeded" do
      user = create_user!()
      company = create_company!(user)
      create_company_bank_account!(company)

      activate_billing_plan!(company, "starter")

      for _ <- 1..49 do
        assert {:ok, _event} =
                 Billing.record_document_usage(company.id, "invoice", Ecto.UUID.generate())
      end

      invoice_1 = create_invoice_with_items!(user, company)
      invoice_2 = create_invoice_with_items!(user, company)

      assert {:ok, issued} = Invoicing.issue_invoice_for_user(user.id, invoice_1.id)
      assert issued.status == "issued"

      assert {:error, :business_rule,
              %{
                rule: :quota_exceeded,
                details: %{company_id: cid, used: 50, limit: 50}
              }} =
               Invoicing.issue_invoice_for_user(user.id, invoice_2.id)

      assert cid == company.id
    end
  end

  describe "pay_invoice_for_user/2" do
    test "marks issued invoice as paid" do
      user = create_user!()
      company = create_company!(user)
      create_company_bank_account!(company)
      invoice = create_invoice_with_items!(user, company)
      {:ok, issued} = Invoicing.issue_invoice_for_user(user.id, invoice.id)

      assert {:ok, paid} = Invoicing.pay_invoice_for_user(user.id, issued.id)
      assert paid.status == "paid"
    end

    test "rejects draft invoice" do
      user = create_user!()
      company = create_company!(user)
      invoice = insert_invoice!(user, company, %{status: "draft"})

      assert {:error, :business_rule, %{rule: :cannot_mark_paid}} =
               Invoicing.pay_invoice_for_user(user.id, invoice.id)
    end

    test "rejects already paid invoice" do
      user = create_user!()
      company = create_company!(user)
      invoice = insert_invoice!(user, company, %{status: "paid"})

      assert {:error, :business_rule, %{rule: :already_paid}} =
               Invoicing.pay_invoice_for_user(user.id, invoice.id)
    end

    test "rejects paying a contract-linked issued invoice while the contract is only issued" do
      user = create_user!()
      company = create_company!(user)
      contract = create_contract!(company, %{"status" => "issued"})

      invoice =
        insert_invoice!(user, company, %{
          status: "issued",
          contract_id: contract.id
        })

      assert {:error, :business_rule,
              %{
                rule: :contract_must_be_signed_to_pay_invoice,
                details: %{
                  invoice_id: invoice_id,
                  contract_id: contract_id,
                  contract_status: "issued"
                }
              }} =
               Invoicing.pay_invoice_for_user(user.id, invoice.id)

      assert invoice_id == invoice.id
      assert contract_id == contract.id
    end

    test "allows paying a contract-linked issued invoice when the contract is signed" do
      user = create_user!()
      company = create_company!(user)
      contract = create_contract!(company, %{"status" => "signed"})

      invoice =
        insert_invoice!(user, company, %{
          status: "issued",
          contract_id: contract.id
        })

      assert {:ok, paid} = Invoicing.pay_invoice_for_user(user.id, invoice.id)
      assert paid.status == "paid"
    end
  end
end
