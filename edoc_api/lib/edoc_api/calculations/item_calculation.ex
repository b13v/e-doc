defmodule EdocApi.Calculations.ItemCalculation do
  @moduledoc """
  Shared calculation logic for invoice and contract items.

  Provides consistent amount calculation regardless of whether qty is
  stored as integer (invoices) or decimal (contracts).
  """

  alias Ecto.Changeset

  @decimal_precision 2

  @doc """
  Computes the amount for an item based on qty and unit_price.

  Works with both integer and decimal qty values. The result is rounded
  to #{@decimal_precision} decimal places.

  ## Examples

      iex> ItemCalculation.compute_amount(2, Decimal.new("100.00"))
      #Decimal<200.00>

      iex> ItemCalculation.compute_amount(Decimal.new("2.5"), Decimal.new("100.00"))
      #Decimal<250.00>
  """
  @spec compute_amount(integer() | Decimal.t(), Decimal.t()) :: Decimal.t()
  def compute_amount(qty, %Decimal{} = unit_price) when is_integer(qty) do
    unit_price
    |> Decimal.mult(Decimal.new(qty))
    |> Decimal.round(@decimal_precision)
  end

  def compute_amount(%Decimal{} = qty, %Decimal{} = unit_price) do
    unit_price
    |> Decimal.mult(qty)
    |> Decimal.round(@decimal_precision)
  end

  def compute_amount(qty, %Decimal{} = unit_price) when is_binary(qty) do
    case Decimal.parse(qty) do
      {%Decimal{} = qty_dec, _} ->
        compute_amount(qty_dec, unit_price)

      _ ->
        nil
    end
  end

  def compute_amount(_qty, _unit_price), do: nil

  @doc """
  Changeset helper that computes and sets the amount field.

  Reads :qty and :unit_price from the changeset, computes the amount,
  and puts it as a change. If either value is missing or invalid,
  the changeset is returned unchanged.

  ## Usage

      changeset
      |> ItemCalculation.compute_amount_changeset()
      |> validate_number(:amount, greater_than: 0)
  """
  @spec compute_amount_changeset(Changeset.t()) :: Changeset.t()
  def compute_amount_changeset(%Changeset{} = changeset) do
    qty = Changeset.get_field(changeset, :qty)
    unit_price = Changeset.get_field(changeset, :unit_price)

    case to_decimal(unit_price) do
      nil ->
        changeset

      price_dec ->
        case compute_amount(qty, price_dec) do
          nil -> changeset
          amount -> Changeset.put_change(changeset, :amount, amount)
        end
    end
  end

  # Private helper to ensure we have a Decimal for unit_price
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(_), do: nil
end
