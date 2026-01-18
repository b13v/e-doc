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

  @required_fields ~w(number date company_id)a
  @optional_fields ~w(title)a

  def changeset(contract, attrs) do
    contract
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:number, name: :contracts_company_id_number_index)
  end
end
