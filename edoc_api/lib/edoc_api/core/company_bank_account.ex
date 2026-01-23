defmodule EdocApi.Core.CompanyBankAccount do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias EdocApi.Validators.Iban
  alias EdocApi.Repo

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
    |> unique_constraint(:company_id,
      name: :company_bank_accounts_single_default,
      message: "only one default bank account per company"
    )
  end

  @doc """
  Creates a changeset for setting this bank account as the default.
  Does NOT reset other defaults - that must be done at transaction level
  to avoid race conditions where validation fails after reset.

  See reset_all_defaults/1 for the transaction-safe pattern.
  """
  def set_as_default_changeset(acc, attrs, company_id) do
    acc
    |> changeset(attrs, company_id)
    |> put_change(:is_default, true)
  end

  @doc """
  Resets all default bank accounts for a company to false.
  Should be called BEFORE setting a new default within a transaction.
  """
  def reset_all_defaults(company_id) do
    from(a in __MODULE__,
      where: a.company_id == ^company_id,
      where: a.is_default == true
    )
    |> Repo.update_all(set: [is_default: false])
  end

  @doc """
  Gets the default bank account for a company.
  Returns nil if no default is set.
  """
  def get_default_account(company_id) do
    __MODULE__
    |> where([a], a.company_id == ^company_id and a.is_default == true)
    |> order_by([a], desc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
