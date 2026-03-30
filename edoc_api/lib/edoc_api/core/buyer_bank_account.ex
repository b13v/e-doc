defmodule EdocApi.Core.BuyerBankAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Core.Bank
  alias EdocApi.Validators.Iban

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "buyer_bank_accounts" do
    field(:iban, :string)
    field(:bic, :string)
    field(:is_default, :boolean, default: false)

    belongs_to(:buyer, EdocApi.Core.Buyer)
    belongs_to(:bank, Bank)

    timestamps(type: :utc_datetime)
  end

  @required ~w(bank_id)a
  @optional ~w(iban bic is_default)a

  def changeset(account, attrs, buyer_id) do
    account
    |> cast(attrs, @required ++ @optional)
    |> put_change(:buyer_id, buyer_id)
    |> validate_required(@required ++ [:buyer_id])
    |> normalize_fields()
    |> validate_iban_if_present()
    |> validate_bic_if_present()
    |> unique_constraint(:buyer_id,
      name: :buyer_bank_accounts_single_default,
      message: "only one default bank account per buyer"
    )
    |> unique_constraint(:iban, name: :buyer_bank_accounts_buyer_id_iban_index)
  end

  defp normalize_fields(changeset) do
    changeset
    |> update_change(:iban, &Iban.normalize/1)
    |> update_change(:bic, fn bic ->
      bic
      |> String.trim()
      |> String.upcase()
    end)
  end

  defp validate_iban_if_present(changeset) do
    case get_field(changeset, :iban) do
      nil -> changeset
      "" -> put_change(changeset, :iban, nil)
      _ -> Iban.validate(changeset, :iban)
    end
  end

  defp validate_bic_if_present(changeset) do
    case get_field(changeset, :bic) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :bic, nil)

      _ ->
        validate_format(changeset, :bic, ~r/^[A-Z0-9]{6,11}$/,
          message: "BIC/SWIFT must be 6-11 chars A-Z0-9"
        )
    end
  end
end
