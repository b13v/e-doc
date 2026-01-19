defmodule EdocApi.Core.CompanyBankAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Validators.Iban

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "company_bank_accounts" do
    field(:label, :string)
    field(:iban, :string)
    field(:is_default, :boolean, default: false)

    belongs_to(:company, EdocApi.Core.Company)
    belongs_to(:bank, EdocApi.Core.Bank)
    belongs_to(:kbe_code, EdocApi.Core.KbeCode)
    belongs_to(:knp_code, EdocApi.Core.KnpCode)

    timestamps(type: :utc_datetime)
  end

  @required ~w(label iban bank_id kbe_code_id knp_code_id)a
  @optional ~w(is_default)a

  def changeset(acc, attrs, company_id) do
    acc
    |> cast(attrs, @required ++ @optional)
    |> put_change(:company_id, company_id)
    |> validate_required(@required ++ [:company_id])
    |> update_change(:label, &String.trim/1)
    |> update_change(:iban, &Iban.normalize/1)
    |> Iban.validate(:iban)
    |> unique_constraint(:iban, name: :company_bank_accounts_company_id_iban_index)
  end
end
