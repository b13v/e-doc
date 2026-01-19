defmodule EdocApi.Validators.BinIin do
  @moduledoc """
  Shared BIN/IIN normalization and validation for Kazakhstan tax identifiers.
  Single source of truth for BIN/IIN handling across all schemas.

  BIN (Business Identification Number) - for legal entities
  IIN (Individual Identification Number) - for individuals
  Both are 12-digit numbers in Kazakhstan.
  """

  import Ecto.Changeset

  @bin_iin_length 12
  @bin_iin_pattern ~r/^\d{12}$/

  @doc """
  Normalizes BIN/IIN: removes all non-digit characters.

  ## Examples

      iex> EdocApi.Validators.BinIin.normalize("123-456-789-012")
      "123456789012"

      iex> EdocApi.Validators.BinIin.normalize(nil)
      nil
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    String.replace(value, ~r/\D+/, "")
  end

  @doc """
  Validates BIN/IIN format on a changeset field.
  Checks that the value is exactly 12 digits.
  """
  @spec validate(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate(changeset, field) do
    changeset
    |> validate_length(field, is: @bin_iin_length)
    |> validate_format(field, @bin_iin_pattern, message: "must contain exactly 12 digits")
  end

  @doc """
  Returns the required length for BIN/IIN.
  """
  def length, do: @bin_iin_length

  @doc """
  Returns the BIN/IIN format regex pattern.
  """
  def pattern, do: @bin_iin_pattern
end
