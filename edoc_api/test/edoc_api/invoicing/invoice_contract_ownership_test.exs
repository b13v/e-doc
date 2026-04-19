defmodule EdocApi.Invoicing.InvoiceContractOwnershipTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Invoicing
  alias EdocApi.Monetization
  import EdocApi.TestFixtures

  describe "create_invoice_for_user/3" do
    test "rejects contract from another company" do
      user = create_user!()
      company_a = create_company!(user)
      other_user = create_user!()
      company_b = create_company!(other_user)
      contract = create_contract!(company_a)

      # Company B needs a bank account to create invoices
      create_company_bank_account!(company_b)

      attrs = invoice_attrs(%{"contract_id" => contract.id})

      assert {:error, :validation, %{changeset: cs}} =
               Invoicing.create_invoice_for_user(user.id, company_b.id, attrs)

      assert {"does not belong to company", _} = Keyword.get(cs.errors, :contract_id)
    end

    test "accepts contract from same company" do
      user = create_user!()
      company = create_company!(user)
      contract = create_contract!(company)

      # Company needs a bank account to create invoices
      create_company_bank_account!(company)

      attrs = invoice_attrs(%{"contract_id" => contract.id})

      assert {:ok, invoice} = Invoicing.create_invoice_for_user(user.id, company.id, attrs)
      assert invoice.contract_id == contract.id
    end

    test "treats blank bank_account_id as nil and uses default account" do
      user = create_user!()
      company = create_company!(user)
      default_account = create_company_bank_account!(company)

      attrs =
        invoice_attrs(%{
          "bank_account_id" => ""
        })

      assert {:ok, invoice} = Invoicing.create_invoice_for_user(user.id, company.id, attrs)
      assert invoice.bank_account_id == default_account.id
    end

    test "blocks creating invoice when the trial document limit is exhausted" do
      user = create_user!()
      company = create_company!(user)
      create_company_bank_account!(company)

      for _ <- 1..10 do
        assert {:ok, _quota} =
                 Monetization.consume_document_quota(
                   company.id,
                   "invoice",
                   Ecto.UUID.generate(),
                   "invoice_issued"
                 )
      end

      assert {:error, :business_rule, %{rule: :quota_exceeded, details: %{used: 10, limit: 10}}} =
               Invoicing.create_invoice_for_user(user.id, company.id, invoice_attrs())
    end
  end

  describe "invoice source contracts" do
    test "returns only signed contracts without any invoices" do
      user = create_user!()
      company = create_company!(user)
      create_company_bank_account!(company)

      {:ok, buyer} =
        EdocApi.Buyers.create_buyer_for_company(company.id, %{
          "name" => "Contract Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      eligible_contract =
        create_contract!(company, %{"status" => "signed", "buyer_id" => buyer.id})

      used_draft_contract =
        create_contract!(company, %{"status" => "signed", "buyer_id" => buyer.id})

      used_issued_contract =
        create_contract!(company, %{"status" => "signed", "buyer_id" => buyer.id})

      used_paid_contract =
        create_contract!(company, %{"status" => "signed", "buyer_id" => buyer.id})

      issued_only_contract =
        create_contract!(company, %{"status" => "issued", "buyer_id" => buyer.id})

      _draft_invoice =
        create_invoice_with_items!(user, company, %{"contract_id" => used_draft_contract.id})

      issued_invoice =
        create_invoice_with_items!(user, company, %{"contract_id" => used_issued_contract.id})

      assert {:ok, _issued} = Invoicing.issue_invoice_for_user(user.id, issued_invoice.id)

      paid_invoice =
        create_invoice_with_items!(user, company, %{"contract_id" => used_paid_contract.id})

      assert {:ok, issued_paid_invoice} =
               Invoicing.issue_invoice_for_user(user.id, paid_invoice.id)

      assert {:ok, _paid} = Invoicing.pay_invoice_for_user(user.id, issued_paid_invoice.id)

      contracts = Invoicing.list_invoice_source_contracts_for_user(user.id)

      assert Enum.map(contracts, & &1.id) == [eligible_contract.id]

      assert {:ok, _contract} =
               Invoicing.get_invoice_source_contract_for_user(user.id, eligible_contract.id)

      assert {:error, :not_found} =
               Invoicing.get_invoice_source_contract_for_user(user.id, used_draft_contract.id)

      assert {:error, :not_found} =
               Invoicing.get_invoice_source_contract_for_user(user.id, used_issued_contract.id)

      assert {:error, :not_found} =
               Invoicing.get_invoice_source_contract_for_user(user.id, used_paid_contract.id)

      assert {:error, :not_found} =
               Invoicing.get_invoice_source_contract_for_user(user.id, issued_only_contract.id)
    end
  end

  describe "overdue invoices" do
    test "returns only issued unpaid invoices more than one day past due for the company" do
      owner = create_user!()
      company = create_company!(owner)
      create_company_bank_account!(company)

      member = create_user!()

      {:ok, _invite} =
        Monetization.invite_member(company.id, %{
          "email" => member.email,
          "role" => "member"
        })

      [_membership_id] = Monetization.accept_pending_memberships_for_user(member)

      today = Date.utc_today()

      overdue =
        insert_invoice!(owner, company, %{
          number: "00000001001",
          status: "issued",
          due_date: Date.add(today, -2)
        })

      _paid_overdue =
        insert_invoice!(owner, company, %{
          number: "00000001002",
          status: "paid",
          due_date: Date.add(today, -3)
        })

      _draft_overdue =
        insert_invoice!(owner, company, %{
          number: "00000001003",
          status: "draft",
          due_date: Date.add(today, -4)
        })

      _yesterday_due =
        insert_invoice!(owner, company, %{
          number: "00000001004",
          status: "issued",
          due_date: Date.add(today, -1)
        })

      _no_due_date =
        insert_invoice!(owner, company, %{
          number: "00000001005",
          status: "issued",
          due_date: nil
        })

      assert [listed] = Invoicing.list_overdue_invoices_for_user(member.id)
      assert listed.id == overdue.id
      assert Invoicing.count_overdue_invoices_for_user(member.id) == 1
    end
  end
end
