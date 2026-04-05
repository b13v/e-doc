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
end
