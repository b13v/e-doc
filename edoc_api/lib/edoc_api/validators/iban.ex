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
  Checks length (15-34 chars), format (2 letters + 2 digits + alphanumeric),
  and checksum (ISO 13616 mod-97).
  """
  @spec validate(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate(changeset, field) do
    changeset
    |> validate_length(field, min: @iban_min_length, max: @iban_max_length)
    |> validate_format(field, @iban_pattern, message: "invalid IBAN format")
    |> validate_change(field, fn
      ^field, nil ->
        []

      ^field, "" ->
        []

      ^field, value when is_binary(value) ->
        if valid_checksum?(value) do
          []
        else
          [{field, "has invalid checksum"}]
        end

      ^field, _value ->
        []
    end)
  end

  @doc """
  Validates IBAN checksum using ISO 13616 mod-97.
  """
  @spec valid_checksum?(String.t()) :: boolean()
  def valid_checksum?(value) when is_binary(value) do
    iban = normalize(value)

    if String.match?(iban, @iban_pattern) and
         String.length(iban) >= @iban_min_length and
         String.length(iban) <= @iban_max_length do
      iban
      |> String.slice(4..-1//1)
      |> Kernel.<>(String.slice(iban, 0, 4))
      |> String.graphemes()
      |> Enum.map_join(&char_to_number/1)
      |> mod97_remainder()
      |> Kernel.==(1)
    else
      false
    end
  end

  def valid_checksum?(_), do: false

  @doc """
  Returns the IBAN format regex pattern.
  """
  def pattern, do: @iban_pattern

  @doc """
  Returns {min, max} length tuple.
  """
  def length_range, do: {@iban_min_length, @iban_max_length}

  defp mod97_remainder(number_string) do
    number_string
    |> String.graphemes()
    |> Enum.reduce(0, fn digit, acc ->
      rem(acc * 10 + String.to_integer(digit), 97)
    end)
  end

  defp char_to_number(char) do
    case Integer.parse(char) do
      {digit, ""} -> Integer.to_string(digit)
      _ -> Integer.to_string(:binary.first(char) - ?A + 10)
    end
  end
end
