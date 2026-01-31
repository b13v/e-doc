defmodule EdocApi.TestFixtures do
  import Ecto.Query

  alias EdocApi.Accounts
  alias EdocApi.Companies
  alias EdocApi.Payments
  alias EdocApi.Invoicing
  alias EdocApi.Core.Contract
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
    # NOTE: bank_name, iban, bank_id, kbe_code_id, knp_code_id are deprecated
    # Use create_company_bank_account! instead
    Map.merge(
      %{
        "name" => "Acme LLC",
        "legal_form" => "LLC",
        "bin_iin" => "123456789012",
        "city" => "Almaty",
        "address" => "Some Street 1",
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
    # Ensure company has a bank account
    _bank_account = ensure_company_has_bank_account(company)

    {:ok, invoice} = Invoicing.create_invoice_for_user(user.id, company.id, invoice_attrs(attrs))
    invoice
  end

  defp ensure_company_has_bank_account(company) do
    import Ecto.Query

    existing =
      CompanyBankAccount
      |> where([a], a.company_id == ^company.id and a.is_default == true)
      |> Repo.one()

    case existing do
      nil ->
        # Try to find any bank account for this company
        any_account =
          CompanyBankAccount
          |> where([a], a.company_id == ^company.id)
          |> Repo.one()

        case any_account do
          nil ->
            account = create_company_bank_account!(company)
            # Set as default since it's the only account - returns the updated account
            Payments.set_default_bank_account_for_company!(company.id, account.id)

          account ->
            # Found an account but it's not default - set it as default
            Payments.set_default_bank_account_for_company!(company.id, account.id)
        end

      account ->
        account
    end
  end

  def create_contract!(company, attrs \\ %{}) do
    number = "C-#{System.unique_integer([:positive])}"

    attrs =
      Map.merge(
        %{
          "number" => number,
          "issue_date" => Date.utc_today(),
          "buyer_name" => "Test Buyer LLC",
          "buyer_bin_iin" => "987654321098",
          "buyer_address" => "Test Buyer Address"
        },
        attrs
      )

    %Contract{}
    |> Contract.changeset(attrs, company.id)
    |> Repo.insert!()
  end

  def insert_invoice!(user, company, overrides \\ %{}) do
    # Get or create a bank account for the company
    bank_account = ensure_company_has_bank_account(company)

    base = %Invoice{
      number: "0000000001",
      service_name: "Consulting",
      issue_date: Date.utc_today(),
      currency: "KZT",
      seller_name: company.name,
      seller_bin_iin: company.bin_iin,
      seller_address: company.address,
      seller_iban: bank_account.iban,
      buyer_name: "Buyer LLC",
      buyer_bin_iin: "123456789012",
      buyer_address: "Buyer Address",
      subtotal: Decimal.new("100.00"),
      vat_rate: 0,
      vat: Decimal.new("0.00"),
      total: Decimal.new("100.00"),
      status: "draft",
      company_id: company.id,
      user_id: user.id,
      bank_account_id: bank_account.id
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

    existing_accounts_count =
      from(a in CompanyBankAccount, where: a.company_id == ^company.id)
      |> Repo.aggregate(:count)

    is_default =
      case Map.get(overrides, "is_default") do
        nil when existing_accounts_count == 0 -> true
        nil -> false
        val -> val
      end

    attrs =
      %{
        "label" => "Main account",
        "iban" => unique_iban(),
        "bank_id" => bank_id,
        "kbe_code_id" => kbe_code_id,
        "knp_code_id" => knp_code_id,
        "is_default" => is_default
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

    # Return existing code or create new one
    case Repo.get_by(KbeCode, code: code) do
      nil ->
        Repo.insert!(%KbeCode{code: code, description: "Test KBE #{code}"})

      existing ->
        existing
    end
  end

  defp create_knp_code! do
    code =
      System.unique_integer([:positive])
      |> rem(1000)
      |> Integer.to_string()
      |> String.pad_leading(3, "0")

    # Return existing code or create new one
    case Repo.get_by(KnpCode, code: code) do
      nil ->
        Repo.insert!(%KnpCode{code: code, description: "Test KNP #{code}"})

      existing ->
        existing
    end
  end

  defp unique_iban do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string()
      |> String.pad_leading(11, "0")

    "KZ00#{suffix}"
  end
end
