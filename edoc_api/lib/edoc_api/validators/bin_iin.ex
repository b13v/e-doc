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
  Checks that the value is exactly 12 digits (Kazakhstan format).

  Note: Full checksum validation is currently disabled as the correct
  Kazakhstan BIN/IIN checksum algorithm needs verification. Format
  validation (12 digits) is still enforced.
  """
  @spec validate(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate(changeset, field) do
    changeset
    |> validate_length(field, is: @bin_iin_length)
    |> validate_format(field, @bin_iin_pattern, message: "must contain exactly 12 digits")

    # TODO: Re-enable checksum validation once correct algorithm is confirmed
    # |> validate_checksum(field)
  end

  @doc """
  Validates the checksum of a BIN/IIN number.
  Kazakhstan BIN/IIN uses a weighted sum algorithm where the 12th digit
  is calculated from the first 11 digits.

  For IIN (Individual Identification Number):
  - Format: YYMMDDCSSSSK where:
    - YY = year of birth (00-99)
    - MM = month (01-12)
    - DD = day (01-31)
    - C = century (3-4 for 1900s, 5-6 for 2000s)
    - SSSS = serial number
    - K = check digit

  Checksum calculation (ISO 7064 MOD 11-2):
  - Weights: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  - Sum = Σ(digit[i] * weight[i]) for i = 0 to 10
  - remainder = sum mod 11
  - If remainder < 2: check_digit = remainder
  - Else: check_digit = 11 - remainder
  """
  @spec valid_checksum?(String.t()) :: boolean()
  def valid_checksum?(value) when is_binary(value) do
    case String.length(value) do
      12 -> validate_kazakhstan_checksum(value)
      _ -> false
    end
  end

  def valid_checksum?(_), do: false

  # Kazakhstan BIN/IIN checksum validation
  # Weights for first calculation attempt
  @weights [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  # Alternative weights when first remainder is 10
  @alt_weights [3, 4, 5, 6, 7, 8, 9, 10, 11, 1, 2]

  defp validate_kazakhstan_checksum(<<digits::binary-size(11), check_digit_str::binary-size(1)>>) do
    digit_list =
      digits
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)

    check_digit = String.to_integer(check_digit_str)

    # Calculate using primary weights
    primary_remainder = calculate_checksum(digit_list, @weights)

    expected_check_digit =
      case primary_remainder do
        10 ->
          # Use alternative weights if primary gives 10
          case calculate_checksum(digit_list, @alt_weights) do
            10 -> 10
            alt_remainder -> alt_remainder
          end

        remainder ->
          remainder
      end

    expected_check_digit == check_digit
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
