defmodule EdocApi.Core.Contract do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contracts" do
    field(:number, :string)
    field(:date, :date)
    field(:title, :string)

    belongs_to(:company, EdocApi.Core.Company)
    has_many(:invoices, EdocApi.Core.Invoice)

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(number date)a
  @optional_fields ~w(title)a

  @doc """
  company_id is NOT accepted from attrs.
  It must be passed explicitly from the authenticated user context.
  """
  def changeset(contract, attrs, company_id) do
    contract
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> put_change(:company_id, company_id)
    |> validate_required(@required_fields ++ [:company_id])
    |> unique_constraint(:number, name: :contracts_company_id_number_index)
  end
end
