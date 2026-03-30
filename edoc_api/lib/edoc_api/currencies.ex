defmodule EdocApi.Currencies do
  @moduledoc """
  Currency configuration and precision management for KZT (Kazakhstani Tenge).

  The application only operates in Kazakhstan and uses KZT exclusively.
  All monetary calculations use 2 decimal places (standard for KZT).
  """

  # KZT precision (Kazakhstani Tenge)
  @default_precision 2

  # Only KZT is supported (Kazakhstan-only application)
  @supported_currencies ~w(KZT)

  @doc """
  Returns the list of supported currency codes.
  Only KZT is supported for this Kazakhstan-only application.

  ## Examples

      iex> EdocApi.Currencies.supported_currencies()
      ["KZT"]

  """
  @spec supported_currencies() :: [String.t()]
  def supported_currencies, do: @supported_currencies

  @doc """
  Checks if a currency code is supported.

  ## Examples

      iex> EdocApi.Currencies.supported?("KZT")
      true

      iex> EdocApi.Currencies.supported?("USD")
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
  Returns the decimal precision for KZT.
  KZT uses 2 decimal places.

  ## Examples

      iex> EdocApi.Currencies.precision("KZT")
      2

  """
  @spec precision(String.t() | atom()) :: non_neg_integer()
  def precision(currency_code \\ "KZT")

  def precision("KZT"), do: 2
  def precision(:KZT), do: 2

  # Fallback to default precision for any other input
  def precision(_), do: @default_precision

  @doc """
  Rounds a decimal value using KZT precision (2 decimal places).

  ## Examples

      iex> EdocApi.Currencies.round_currency(Decimal.new("123.456"), "KZT")
      #Decimal<123.46>

  """
  @spec round_currency(Decimal.t(), String.t() | atom()) :: Decimal.t()
  def round_currency(%Decimal{} = decimal, currency_code \\ "KZT") do
    Decimal.round(decimal, precision(currency_code))
  end

  @doc """
  Returns the default precision for the application (2 for KZT).
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
