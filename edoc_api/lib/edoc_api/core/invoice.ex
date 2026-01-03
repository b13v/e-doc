defmodule EdocApi.Core.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

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

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(
    number
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
    total
    status
  )a

  @optional_fields ~w(due_date subtotal vat)a

  @allowed_statuses ~w(draft issued paid void)
  @allowed_currencies ~w(KZT USD EUR RUB)

  @doc """
  Variant B: user_id/company_id не принимаем из attrs.
  Их ставим из current_user/company.
  """
  def changeset(invoice, attrs, user_id, company_id) do
    invoice
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> put_change(:user_id, user_id)
    |> put_change(:company_id, company_id)
    |> validate_required(@required_fields ++ [:user_id, :company_id])
    |> normalize_fields()
    |> validate_inclusion(:status, @allowed_statuses)
    |> validate_inclusion(:currency, @allowed_currencies)
    |> validate_length(:number, min: 1, max: 64)
    |> validate_length(:service_name, min: 3, max: 255)
    |> validate_bin_iin(:seller_bin_iin)
    |> validate_bin_iin(:buyer_bin_iin)
    |> validate_iban(:seller_iban)
    |> validate_number(:total, greater_than: 0)
    |> unique_constraint(:number, name: :invoices_user_id_number_index)
  end

  defp normalize_fields(changeset) do
    changeset
    |> update_change(:number, &trim_nil/1)
    |> update_change(:service_name, &trim_nil/1)
    |> update_change(:currency, &normalize_currency/1)
    |> update_change(:status, &normalize_status/1)
    |> update_change(:seller_name, &trim_nil/1)
    |> update_change(:seller_address, &trim_nil/1)
    |> update_change(:seller_bin_iin, &digits_only/1)
    |> update_change(:seller_iban, &normalize_iban/1)
    |> update_change(:buyer_name, &trim_nil/1)
    |> update_change(:buyer_address, &trim_nil/1)
    |> update_change(:buyer_bin_iin, &digits_only/1)
  end

  defp trim_nil(nil), do: nil
  defp trim_nil(v) when is_binary(v), do: String.trim(v)

  defp digits_only(nil), do: nil
  defp digits_only(v) when is_binary(v), do: String.replace(v, ~r/\D+/, "")

  defp normalize_iban(nil), do: nil

  defp normalize_iban(v) when is_binary(v),
    do: v |> String.replace(~r/\s+/, "") |> String.upcase()

  defp normalize_currency(nil), do: nil
  defp normalize_currency(v) when is_binary(v), do: v |> String.trim() |> String.upcase()

  defp normalize_status(nil), do: nil
  defp normalize_status(v) when is_binary(v), do: v |> String.trim() |> String.downcase()

  defp validate_bin_iin(changeset, field) do
    changeset
    |> validate_length(field, is: 12)
    |> validate_format(field, ~r/^\d{12}$/, message: "must contain exactly 12 digits")
  end

  defp validate_iban(changeset, field) do
    changeset
    |> validate_length(field, min: 15, max: 34)
    |> validate_format(field, ~r/^[A-Z]{2}\d{2}[A-Z0-9]+$/, message: "invalid IBAN format")
  end
end
