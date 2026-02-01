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
  Checks that the value is exactly 12 digits and has a valid checksum.
  """
  @spec validate(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate(changeset, field) do
    changeset
    |> validate_length(field, is: @bin_iin_length)
    |> validate_format(field, @bin_iin_pattern, message: "must contain exactly 12 digits")
    |> validate_checksum(field)
  end

  @doc """
  Validates the checksum of a BIN/IIN number.
  Kazakhstan BIN/IIN uses a weighted sum algorithm where the 12th digit
  is calculated from the first 11 digits using specific weights.
  """
  @spec valid_checksum?(String.t()) :: boolean()
  def valid_checksum?(value) when is_binary(value) do
    case String.length(value) do
      12 -> validate_kazakhstan_checksum(value)
      _ -> false
    end
  end

  def valid_checksum?(_), do: false

  # Kazakhstan BIN/IIN checksum algorithm:
  # 1. Multiply each of the first 11 digits by weights [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  # 2. Sum all products
  # 3. Take modulo 11
  # 4. If remainder is 10, use alternative weights [3, 4, 5, 6, 7, 8, 9, 10, 11, 1, 2]
  # 5. The result (0-9) should match the 12th digit
  defp validate_kazakhstan_checksum(<<digits::binary-size(11), check_digit::binary-size(1)>>) do
    weights = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    alternative_weights = [3, 4, 5, 6, 7, 8, 9, 10, 11, 1, 2]

    digit_list =
      digits
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)

    expected =
      case calculate_checksum(digit_list, weights) do
        10 -> calculate_checksum(digit_list, alternative_weights)
        remainder -> remainder
      end

    String.to_integer(check_digit) == expected
  end

  defp calculate_checksum(digits, weights) do
    digits
    |> Enum.zip(weights)
    |> Enum.reduce(0, fn {digit, weight}, acc -> acc + digit * weight end)
    |> rem(11)
  end

  defp validate_checksum(changeset, field) do
    value = get_field(changeset, field)

    cond do
      is_nil(value) ->
        changeset

      valid_checksum?(value) ->
        changeset

      true ->
        add_error(changeset, field, "has invalid checksum")
    end
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
