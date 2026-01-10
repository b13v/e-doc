defmodule EdocApi.TestFixtures do
  alias EdocApi.Accounts
  alias EdocApi.Core
  alias EdocApi.Core.Invoice
  alias EdocApi.Core.InvoiceItem
  alias EdocApi.Repo

  def unique_email do
    "user#{System.unique_integer([:positive])}@example.com"
  end

  def create_user!(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{"email" => unique_email(), "password" => "password123"},
        attrs
      )

    {:ok, user} = Accounts.register_user(attrs)
    user
  end

  def company_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Acme LLC",
        "legal_form" => "LLC",
        "bin_iin" => "123456789012",
        "city" => "Almaty",
        "address" => "Some Street 1",
        "bank" => "KZ Bank",
        "iban" => "KZ123456789012345678",
        "phone" => "+7 (777) 123 45 67",
        "representative_name" => "John Doe",
        "representative_title" => "Director",
        "basis" => "Charter",
        "email" => "info@example.com"
      },
      overrides
    )
  end

  def create_company!(user, attrs \\ %{}) do
    {:ok, company, _warnings} = Core.upsert_company_for_user(user.id, company_attrs(attrs))
    company
  end

  def invoice_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "service_name" => "Consulting",
        "issue_date" => Date.utc_today(),
        "currency" => "KZT",
        "buyer_name" => "Buyer LLC",
        "buyer_bin_iin" => "123456789012",
        "buyer_address" => "Buyer Address",
        "vat_rate" => 0,
        "items" => [
          %{"name" => "Service", "qty" => 1, "unit_price" => "100.00"}
        ]
      },
      overrides
    )
  end

  def create_invoice_with_items!(user, company, attrs \\ %{}) do
    {:ok, invoice} = Core.create_invoice_for_user(user.id, company.id, invoice_attrs(attrs))
    invoice
  end

  def insert_invoice!(user, company, overrides \\ %{}) do
    base = %Invoice{
      number: "0000000001",
      service_name: "Consulting",
      issue_date: Date.utc_today(),
      currency: "KZT",
      seller_name: company.name,
      seller_bin_iin: company.bin_iin,
      seller_address: company.address,
      seller_iban: company.iban,
      buyer_name: "Buyer LLC",
      buyer_bin_iin: "123456789012",
      buyer_address: "Buyer Address",
      subtotal: Decimal.new("100.00"),
      vat_rate: 0,
      vat: Decimal.new("0.00"),
      total: Decimal.new("100.00"),
      status: "draft",
      company_id: company.id,
      user_id: user.id
    }

    Repo.insert!(struct(base, overrides))
  end

  def insert_item!(invoice, overrides \\ %{}) do
    base = %InvoiceItem{
      invoice_id: invoice.id,
      name: "Item",
      qty: 1,
      unit_price: Decimal.new("10.00"),
      amount: Decimal.new("10.00")
    }

    Repo.insert!(struct(base, overrides))
  end
end
