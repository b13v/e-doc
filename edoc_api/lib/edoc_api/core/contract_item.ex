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
    |> compute_amount()
    |> validate_number(:amount, greater_than: 0)
    |> put_change(:contract_id, contract_id)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, @required ++ @optional ++ [:contract_id])
    |> validate_required(@required ++ [:contract_id])
    |> validate_number(:qty, greater_than: 0)
    |> validate_number(:unit_price, greater_than: 0)
    |> compute_amount()
    |> validate_number(:amount, greater_than: 0)
  end

  defp compute_amount(changeset) do
    qty = get_field(changeset, :qty)
    unit_price = get_field(changeset, :unit_price)

    with %Decimal{} = qty_dec <- parse_decimal(qty),
         %Decimal{} = price_dec <- parse_decimal(unit_price) do
      amount =
        price_dec
        |> Decimal.mult(qty_dec)
        |> Decimal.round(2)

      put_change(changeset, :amount, amount)
    else
      _ -> changeset
    end
  end

  defp parse_decimal(%Decimal{} = d), do: d
  defp parse_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp parse_decimal(s) when is_binary(s), do: Decimal.parse(s) |> elem(0)
  defp parse_decimal(_), do: nil
end
