defmodule EdocApi.Invoicing.InvoiceIssuanceTest do
  use EdocApi.DataCase, async: true

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
  end
end
