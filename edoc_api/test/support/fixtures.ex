defmodule EdocApi.TestFixtures do
  alias EdocApi.Accounts
  alias EdocApi.Companies
  alias EdocApi.Invoicing
  alias EdocApi.Core.Invoice
  alias EdocApi.Core.InvoiceItem
  alias EdocApi.Core.Bank
  alias EdocApi.Core.KbeCode
  alias EdocApi.Core.KnpCode
  alias EdocApi.Core.CompanyBankAccount
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
        "bank_name" => "KZ Bank",
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
    attrs = ensure_company_payment_refs(attrs)
    {:ok, company, _warnings} = Companies.upsert_company_for_user(user.id, company_attrs(attrs))
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
    {:ok, invoice} = Invoicing.create_invoice_for_user(user.id, company.id, invoice_attrs(attrs))
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

  def create_company_bank_account!(company, overrides \\ %{}) do
    overrides = Map.new(overrides)

    bank_id =
      Map.get(overrides, "bank_id") || Map.get(overrides, :bank_id) || create_bank!().id

    kbe_code_id =
      Map.get(overrides, "kbe_code_id") || Map.get(overrides, :kbe_code_id) ||
        create_kbe_code!().id

    knp_code_id =
      Map.get(overrides, "knp_code_id") || Map.get(overrides, :knp_code_id) ||
        create_knp_code!().id

    attrs =
      %{
        "label" => "Main account",
        "iban" => unique_iban(),
        "bank_id" => bank_id,
        "kbe_code_id" => kbe_code_id,
        "knp_code_id" => knp_code_id,
        "is_default" => true
      }
      |> Map.merge(overrides)

    %CompanyBankAccount{}
    |> CompanyBankAccount.changeset(attrs, company.id)
    |> Repo.insert!()
  end

  defp ensure_company_payment_refs(attrs) do
    attrs = Map.new(attrs)

    attrs =
      if Map.has_key?(attrs, "bank_id") or Map.has_key?(attrs, :bank_id) do
        attrs
      else
        bank = create_bank!()
        attrs |> Map.put("bank_id", bank.id) |> Map.put_new("bank_name", bank.name)
      end

    attrs =
      if Map.has_key?(attrs, "kbe_code_id") or Map.has_key?(attrs, :kbe_code_id) do
        attrs
      else
        kbe = create_kbe_code!()
        Map.put(attrs, "kbe_code_id", kbe.id)
      end

    if Map.has_key?(attrs, "knp_code_id") or Map.has_key?(attrs, :knp_code_id) do
      attrs
    else
      knp = create_knp_code!()
      Map.put(attrs, "knp_code_id", knp.id)
    end
  end

  defp create_bank! do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    bic = "BIC#{String.slice(suffix, 0, 8)}"
    Repo.insert!(%Bank{name: "Test Bank #{suffix}", bic: bic})
  end

  defp create_kbe_code! do
    code =
      System.unique_integer([:positive])
      |> rem(100)
      |> Integer.to_string()
      |> String.pad_leading(2, "0")

    Repo.insert!(%KbeCode{code: code, description: "Test KBE #{code}"})
  end

  defp create_knp_code! do
    code =
      System.unique_integer([:positive])
      |> rem(1000)
      |> Integer.to_string()
      |> String.pad_leading(3, "0")

    Repo.insert!(%KnpCode{code: code, description: "Test KNP #{code}"})
  end

  defp unique_iban do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    "KZ00TEST#{suffix}"
  end
end
