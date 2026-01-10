defmodule EdocApi.Core.InvoiceIssuanceTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Core
  import EdocApi.TestFixtures

  describe "issue_invoice_for_user/2" do
    test "issues a draft invoice with items and positive total" do
      user = create_user!()
      company = create_company!(user)
      invoice = create_invoice_with_items!(user, company)

      assert invoice.status == "draft"
      assert {:ok, issued} = Core.issue_invoice_for_user(user.id, invoice.id)
      assert issued.status == "issued"
    end

    test "rejects already issued invoices" do
      user = create_user!()
      company = create_company!(user)
      invoice = insert_invoice!(user, company, %{status: "issued"})

      assert {:error, :already_issued} = Core.issue_invoice_for_user(user.id, invoice.id)
    end

    test "rejects non-draft status" do
      user = create_user!()
      company = create_company!(user)
      invoice = insert_invoice!(user, company, %{status: "paid"})

      assert {:error, :cannot_issue, %{status: "must be draft to issue"}} =
               Core.issue_invoice_for_user(user.id, invoice.id)
    end

    test "rejects invoices without items" do
      user = create_user!()
      company = create_company!(user)
      invoice = insert_invoice!(user, company, %{total: Decimal.new("100.00")})

      assert {:error, :cannot_issue, %{items: "must have at least 1 item"}} =
               Core.issue_invoice_for_user(user.id, invoice.id)
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

      assert {:error, :cannot_issue, %{total: "must be > 0"}} =
               Core.issue_invoice_for_user(user.id, invoice.id)
    end

    test "rejects unknown invoice id" do
      user = create_user!()

      assert {:error, :invoice_not_found} =
               Core.issue_invoice_for_user(user.id, Ecto.UUID.generate())
    end
  end
end
