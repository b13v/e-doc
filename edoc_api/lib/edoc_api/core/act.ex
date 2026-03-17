defmodule EdocApi.Core.Act do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "acts" do
    field(:number, :string)
    field(:status, :string, default: "draft")
    field(:issue_date, :date)
    field(:actual_date, :date)
    field(:currency, :string, default: "KZT")
    field(:vat_rate, :integer, default: 16)

    field(:seller_name, :string)
    field(:seller_bin_iin, :string)
    field(:seller_address, :string)
    field(:seller_phone, :string)

    field(:buyer_name, :string)
    field(:buyer_bin_iin, :string)
    field(:buyer_address, :string)
    field(:buyer_phone, :string)

    belongs_to(:company, EdocApi.Core.Company)
    belongs_to(:user, EdocApi.Accounts.User)
    belongs_to(:buyer, EdocApi.Core.Buyer)
    belongs_to(:contract, EdocApi.Core.Contract)
    has_many(:items, EdocApi.Core.ActItem, on_replace: :delete)

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(
    number
    issue_date
    currency
    vat_rate
    seller_name
    seller_bin_iin
    seller_address
    buyer_name
    buyer_bin_iin
    buyer_address
    company_id
    user_id
    buyer_id
  )a

  @optional_fields ~w(
    status
    actual_date
    seller_phone
    buyer_phone
    contract_id
  )a

  @allowed_statuses ~w(draft issued signed)

  def changeset(act, attrs) do
    act
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @allowed_statuses)
    |> validate_number(:vat_rate, greater_than_or_equal_to: 0)
    |> unique_constraint(:number, name: :acts_company_id_number_index)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:buyer_id)
    |> foreign_key_constraint(:contract_id)
  end
end
