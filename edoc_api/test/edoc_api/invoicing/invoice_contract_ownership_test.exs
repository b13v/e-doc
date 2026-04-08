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
    test "returns only signed contracts without issued invoices" do
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

      used_contract =
        create_contract!(company, %{"status" => "signed", "buyer_id" => buyer.id})

      issued_only_contract =
        create_contract!(company, %{"status" => "issued", "buyer_id" => buyer.id})

      invoice = create_invoice_with_items!(user, company, %{"contract_id" => used_contract.id})
      assert {:ok, _issued} = Invoicing.issue_invoice_for_user(user.id, invoice.id)

      contracts = Invoicing.list_invoice_source_contracts_for_user(user.id)

      assert Enum.map(contracts, & &1.id) == [eligible_contract.id]

      assert {:ok, _contract} =
               Invoicing.get_invoice_source_contract_for_user(user.id, eligible_contract.id)

      assert {:error, :not_found} =
               Invoicing.get_invoice_source_contract_for_user(user.id, used_contract.id)

      assert {:error, :not_found} =
               Invoicing.get_invoice_source_contract_for_user(user.id, issued_only_contract.id)
    end
  end
end
