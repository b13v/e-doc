defmodule EdocApi.Core.InvoiceCounterTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Core

  import EdocApi.TestFixtures

  test "increments sequentially per company" do
    user = create_user!()
    company = create_company!(user)

    assert Core.next_invoice_number!(company.id) == "0000000001"
    assert Core.next_invoice_number!(company.id) == "0000000002"
  end

  test "sequences are independent per company" do
    user_one = create_user!()
    company_one = create_company!(user_one)

    user_two = create_user!()
    company_two = create_company!(user_two)

    assert Core.next_invoice_number!(company_one.id) == "0000000001"
    assert Core.next_invoice_number!(company_two.id) == "0000000001"
    assert Core.next_invoice_number!(company_one.id) == "0000000002"
  end
end
