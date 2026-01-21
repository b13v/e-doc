defmodule EdocApi.Invoicing.InvoiceContractOwnershipTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Invoicing
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

      assert {:error, %Ecto.Changeset{} = cs} =
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
  end
end
