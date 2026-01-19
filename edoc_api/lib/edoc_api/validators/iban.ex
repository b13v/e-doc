defmodule EdocApi.Validators.Iban do
  @moduledoc """
  Shared IBAN normalization and validation.
  Single source of truth for IBAN handling across all schemas.
  """

  import Ecto.Changeset

  @iban_min_length 15
  @iban_max_length 34
  @iban_pattern ~r/^[A-Z]{2}\d{2}[A-Z0-9]+$/

  @doc """
  Normalizes IBAN: removes whitespace and uppercases.

  ## Examples

      iex> EdocApi.Validators.Iban.normalize("kz 12 3456")
      "KZ123456"

      iex> EdocApi.Validators.Iban.normalize(nil)
      nil
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, "")
    |> String.upcase()
  end

  @doc """
  Validates IBAN format on a changeset field.
  Checks length (15-34 chars) and format (2 letters + 2 digits + alphanumeric).
  """
  @spec validate(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate(changeset, field) do
    changeset
    |> validate_length(field, min: @iban_min_length, max: @iban_max_length)
    |> validate_format(field, @iban_pattern, message: "invalid IBAN format")
  end

  @doc """
  Returns the IBAN format regex pattern.
  """
  def pattern, do: @iban_pattern

  @doc """
  Returns {min, max} length tuple.
  """
  def length_range, do: {@iban_min_length, @iban_max_length}
end
