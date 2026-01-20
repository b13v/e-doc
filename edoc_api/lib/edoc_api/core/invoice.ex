defmodule EdocApi.Core.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Repo
  alias EdocApi.Core.{Contract, CompanyBankAccount}
  alias EdocApi.InvoiceStatus
  alias EdocApi.Validators.{BinIin, Iban}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoices" do
    field(:number, :string)
    field(:service_name, :string)
    field(:issue_date, :date)
    field(:due_date, :date)
    field(:currency, :string)

    field(:seller_name, :string)
    field(:seller_bin_iin, :string)
    field(:seller_address, :string)
    field(:seller_iban, :string)

    field(:buyer_name, :string)
    field(:buyer_bin_iin, :string)
    field(:buyer_address, :string)

    field(:subtotal, :decimal)
    field(:vat, :decimal)
    field(:vat_rate, :integer, default: 0)
    field(:total, :decimal)

    field(:status, :string)

    has_many(:items, EdocApi.Core.InvoiceItem, on_replace: :delete)
    belongs_to(:company, EdocApi.Core.Company)
    belongs_to(:user, EdocApi.Accounts.User)
    belongs_to(:bank_account, EdocApi.Core.CompanyBankAccount)
    belongs_to(:contract, EdocApi.Core.Contract)
    has_one(:bank_snapshot, EdocApi.Core.InvoiceBankSnapshot)

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(
    service_name
    issue_date
    currency
    seller_name
    seller_bin_iin
    seller_address
    seller_iban
    buyer_name
    buyer_bin_iin
    buyer_address
    vat_rate
    )a

  @optional_fields ~w(number due_date subtotal total vat status bank_account_id contract_id)a

  @allowed_statuses InvoiceStatus.all()
  @allowed_currencies ~w(KZT USD EUR RUB)

  @doc """
  user_id/company_id не принимаем из attrs.
  Их ставим из current_user/company.
  """
  def changeset(invoice, attrs, user_id, company_id) do
    invoice
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> put_change(:user_id, user_id)
    |> put_change(:company_id, company_id)
    |> validate_required(@required_fields ++ [:user_id, :company_id])
    |> normalize_fields()
    |> put_default(:status, InvoiceStatus.default())
    |> validate_inclusion(:vat_rate, [0, 16], message: "VAT rate must be 0 or 16")
    |> compute_totals()
    |> validate_number(:total, greater_than: 0)
    |> validate_number(:subtotal, greater_than_or_equal_to: 0)
    |> validate_number(:vat, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, @allowed_statuses)
    |> validate_inclusion(:currency, @allowed_currencies)
    |> validate_number_optional()
    |> validate_length(:service_name, min: 3, max: 255)
    |> BinIin.validate(:seller_bin_iin)
    |> BinIin.validate(:buyer_bin_iin)
    |> Iban.validate(:seller_iban)
    |> unique_constraint(:number, name: :invoices_user_id_number_index)
    |> foreign_key_constraint(:contract_id)
    |> prepare_changes(&validate_contract_ownership/1)
    |> prepare_changes(&validate_bank_account_ownership/1)
  end

  defp normalize_fields(changeset) do
    changeset
    |> update_change(:number, &trim_nil/1)
    |> update_change(:service_name, &trim_nil/1)
    |> update_change(:currency, &normalize_currency/1)
    |> update_change(:status, &normalize_status/1)
    |> update_change(:seller_name, &trim_nil/1)
    |> update_change(:seller_address, &trim_nil/1)
    |> update_change(:seller_bin_iin, &BinIin.normalize/1)
    |> update_change(:seller_iban, &Iban.normalize/1)
    |> update_change(:buyer_name, &trim_nil/1)
    |> update_change(:buyer_address, &trim_nil/1)
    |> update_change(:buyer_bin_iin, &BinIin.normalize/1)
  end

  defp trim_nil(nil), do: nil
  # defp trim_nil(v) when is_binary(v), do: String.trim(v)
  defp trim_nil(v) when is_binary(v) do
    v = String.trim(v)
    if v == "", do: nil, else: v
  end

  defp normalize_currency(nil), do: nil
  defp normalize_currency(v) when is_binary(v), do: v |> String.trim() |> String.upcase()

  defp normalize_status(nil), do: nil
  defp normalize_status(v) when is_binary(v), do: v |> String.trim() |> String.downcase()

  defp validate_number_optional(changeset) do
    case get_field(changeset, :number) do
      nil -> changeset
      "" -> add_error(changeset, :number, "can't be blank")
      _ -> validate_length(changeset, :number, min: 1, max: 32)
    end
  end

  defp validate_contract_ownership(changeset) do
    contract_id = get_change(changeset, :contract_id)
    company_id = get_field(changeset, :company_id)

    cond do
      is_nil(contract_id) or is_nil(company_id) ->
        changeset

      true ->
        case Repo.get(Contract, contract_id) do
          %Contract{company_id: ^company_id} -> changeset
          %Contract{} -> add_error(changeset, :contract_id, "does not belong to company")
          nil -> add_error(changeset, :contract_id, "not found")
        end
    end
  end

  defp validate_bank_account_ownership(changeset) do
    bank_account_id = get_change(changeset, :bank_account_id)
    company_id = get_field(changeset, :company_id)

    cond do
      is_nil(bank_account_id) or is_nil(company_id) ->
        changeset

      true ->
        case Repo.get(CompanyBankAccount, bank_account_id) do
          %CompanyBankAccount{company_id: ^company_id} ->
            changeset

          %CompanyBankAccount{} ->
            add_error(changeset, :bank_account_id, "does not belong to company")

          nil ->
            add_error(changeset, :bank_account_id, "not found")
        end
    end
  end

  defp put_default(changeset, field, value) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, value)
      "" -> put_change(changeset, field, value)
      _ -> changeset
    end
  end

  defp compute_totals(changeset) do
    subtotal = get_field(changeset, :subtotal)
    vat_rate = get_field(changeset, :vat_rate)

    if is_struct(subtotal, Decimal) and is_integer(vat_rate) do
      vat =
        subtotal
        |> Decimal.mult(Decimal.new(vat_rate))
        |> Decimal.div(Decimal.new(100))
        |> Decimal.round(2)

      total =
        subtotal
        |> Decimal.add(vat)
        |> Decimal.round(2)

      changeset
      |> put_change(:vat, vat)
      |> put_change(:total, total)
    else
      changeset
    end
  end
end
