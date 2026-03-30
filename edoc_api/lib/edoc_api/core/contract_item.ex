defmodule EdocApi.Core.ContractItem do
  @moduledoc """
  Contract items represent Appendix №1 of the contract.
  They are stored separately from invoice items because:
  - Different semantics and lifecycle
  - Contracts may generate multiple invoices
  - Invoice items are financial snapshots
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Calculations.ItemCalculation
  alias EdocApi.Core.Contract

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contract_items" do
    field(:code, :string)
    field(:name, :string)
    field(:qty, :decimal)
    field(:unit_price, :decimal)
    field(:amount, :decimal)

    belongs_to(:contract, Contract)

    timestamps(type: :utc_datetime)
  end

  @required ~w(name qty unit_price)a
  @optional ~w(code amount)a

  @doc """
  company_id is NOT accepted from attrs.
  It must be passed explicitly from the contract context.
  """
  def changeset(item, attrs, contract_id) do
    item
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:qty, greater_than: 0)
    |> validate_number(:unit_price, greater_than: 0)
    |> ItemCalculation.compute_amount_changeset()
    |> validate_number(:amount, greater_than: 0)
    |> put_change(:contract_id, contract_id)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, @required ++ @optional ++ [:contract_id])
    |> validate_required(@required ++ [:contract_id])
    |> validate_number(:qty, greater_than: 0)
    |> validate_number(:unit_price, greater_than: 0)
    |> ItemCalculation.compute_amount_changeset()
    |> validate_number(:amount, greater_than: 0)
  end
end
