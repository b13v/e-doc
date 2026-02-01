defmodule EdocApi.Invoicing.InvoiceCounterTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Invoicing
  alias EdocApi.Core.InvoiceCounter
  alias EdocApi.Repo

  import EdocApi.TestFixtures

  test "increments sequentially per company" do
    user = create_user!()
    company = create_company!(user)

    assert Invoicing.next_invoice_number!(company.id) == "00000000001"
    assert Invoicing.next_invoice_number!(company.id) == "00000000002"
  end

  test "sequences are independent per company" do
    user_one = create_user!()
    company_one = create_company!(user_one)

    user_two = create_user!()
    company_two = create_company!(user_two)

    assert Invoicing.next_invoice_number!(company_one.id) == "00000000001"
    assert Invoicing.next_invoice_number!(company_two.id) == "00000000001"
    assert Invoicing.next_invoice_number!(company_one.id) == "00000000002"
  end

  test "handles large invoice numbers correctly" do
    user = create_user!()
    company = create_company!(user)

    # Set counter to near maximum (9,999,999,998)
    Repo.insert!(%InvoiceCounter{
      company_id: company.id,
      next_seq: 9_999_999_999
    })

    # Should get 9,999,999,998
    assert Invoicing.next_invoice_number!(company.id) == "09999999998"
    # Should get 9,999,999,999
    assert Invoicing.next_invoice_number!(company.id) == "09999999999"
  end

  test "raises error when counter overflows maximum" do
    user = create_user!()
    company = create_company!(user)

    # Set counter to exceed maximum (next_seq = 10,000,000,001)
    Repo.insert!(%InvoiceCounter{
      company_id: company.id,
      next_seq: 10_000_000_001
    })

    # Should raise error because seq = next_seq - 1 = 10,000,000,000 > 9,999,999,999
    assert_raise RuntimeError, ~r/invoice number counter overflow/, fn ->
      Invoicing.next_invoice_number!(company.id)
    end
  end

  test "raises descriptive error with company information on overflow" do
    user = create_user!()
    company = create_company!(user)

    Repo.insert!(%InvoiceCounter{
      company_id: company.id,
      next_seq: 10_000_000_001
    })

    assert_raise RuntimeError,
                 ~r/maximum invoice number \(9,999,999,999\) exceeded for company/,
                 fn ->
                   Invoicing.next_invoice_number!(company.id)
                 end
  end
end
