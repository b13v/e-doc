defmodule EdocApi.Currencies do
  @moduledoc """
  Currency configuration and precision management.

  Provides currency-specific precision settings and utility functions
  for monetary calculations throughout the application.
  """

  # Default currency precision (KZT - Kazakhstani Tenge)
  @default_precision 2

  # Supported currencies for the application
  @supported_currencies ~w(KZT USD EUR RUB)

  @doc """
  Returns the list of supported currency codes.

  ## Examples

      iex> EdocApi.Currencies.supported_currencies()
      ["KZT", "USD", "EUR", "RUB"]

  """
  @spec supported_currencies() :: [String.t()]
  def supported_currencies, do: @supported_currencies

  @doc """
  Checks if a currency code is supported.

  ## Examples

      iex> EdocApi.Currencies.supported?("KZT")
      true

      iex> EdocApi.Currencies.supported?("GBP")
      false

  """
  @spec supported?(String.t() | atom()) :: boolean()
  def supported?(currency) do
    code = to_string_code(currency)
    code in @supported_currencies
  end

  # Private helper to normalize currency code to string
  defp to_string_code(code) when is_atom(code), do: Atom.to_string(code) |> String.upcase()
  defp to_string_code(code) when is_binary(code), do: String.upcase(code)

  @doc """
  Returns the decimal precision for the given currency code.

  ## Examples

      iex> EdocApi.Currencies.precision("KZT")
      2

      iex> EdocApi.Currencies.precision("USD")
      2

      iex> EdocApi.Currencies.precision("JPY")
      0
  """
  @spec precision(String.t() | atom()) :: non_neg_integer()
  def precision(currency_code \\ "KZT")

  def precision("KZT"), do: 2
  def precision(:KZT), do: 2

  # Additional common currencies (can be expanded as needed)
  def precision("USD"), do: 2
  def precision(:USD), do: 2
  def precision("EUR"), do: 2
  def precision(:EUR), do: 2
  def precision("RUB"), do: 2
  def precision(:RUB), do: 2
  # Japanese Yen has no decimal places
  def precision("JPY"), do: 0
  def precision(:JPY), do: 0

  # Fallback to default precision for unknown currencies
  def precision(_), do: @default_precision

  @doc """
  Rounds a decimal value using the appropriate precision for the given currency.

  ## Examples

      iex> EdocApi.Currencies.round_currency(Decimal.new("123.456"), "KZT")
      #Decimal<123.46>

      iex> EdocApi.Currencies.round_currency(Decimal.new("123.456"), "JPY")
      #Decimal<123>
  """
  @spec round_currency(Decimal.t(), String.t() | atom()) :: Decimal.t()
  def round_currency(%Decimal{} = decimal, currency_code \\ "KZT") do
    Decimal.round(decimal, precision(currency_code))
  end

  @doc """
  Returns the default precision for the application.
  """
  @spec default_precision() :: non_neg_integer()
  def default_precision, do: @default_precision

  @doc """
  Rounds a decimal value using the default precision.
  """
  @spec round_default(Decimal.t()) :: Decimal.t()
  def round_default(%Decimal{} = decimal) do
    Decimal.round(decimal, @default_precision)
  end
end
