defmodule EdocApi.VatRates do
  @moduledoc """
  VAT (Value Added Tax) rate configuration and validation.

  Provides country-specific VAT rates and validation functions for invoices.
  Supports historical rate changes and different rates by country.

  ## VAT Rates by Country

  | Country | Standard Rate | Notes |
  |---------|---------------|-------|
  | KZ      | 16%           | Kazakhstan |
  | RU      | 20%           | Russia |
  | DEFAULT | 16%           | Fallback for unknown countries |

  ## Examples

      iex> VatRates.for_country("KZ")
      [0, 16]

      iex> VatRates.standard_rate("KZ")
      16

      iex> VatRates.validate_rate(changeset, :vat_rate, "KZ")

  """

  import Ecto.Changeset

  # VAT rates by country code (ISO 3166-1 alpha-2)
  # Each list includes zero-rated (0) and the standard rate(s)
  @rates %{
    # Kazakhstan
    "KZ" => [0, 16],
    # Russia - 20% standard rate
    "RU" => [0, 20],
    # Default fallback
    "DEFAULT" => [0, 16]
  }

  # Default country code for operations
  @default_country "KZ"

  @type country_code :: String.t()
  @type vat_rate :: non_neg_integer()

  @doc """
  Returns all allowed VAT rates for a given country.

  ## Examples

      iex> EdocApi.VatRates.for_country("KZ")
      [0, 16]

      iex> EdocApi.VatRates.for_country("RU")
      [0, 20]

      iex> EdocApi.VatRates.for_country("UNKNOWN")
      [0, 16]

  """
  @spec for_country(country_code()) :: [vat_rate()]
  def for_country(country_code \\ @default_country) do
    normalized = normalize_country_code(country_code)
    Map.get(@rates, normalized, @rates["DEFAULT"])
  end

  @doc """
  Returns the standard (non-zero) VAT rate for a country.

  ## Examples

      iex> EdocApi.VatRates.standard_rate("KZ")
      16

      iex> EdocApi.VatRates.standard_rate("RU")
      20

  """
  @spec standard_rate(country_code()) :: vat_rate()
  def standard_rate(country_code \\ @default_country) do
    country_code
    |> for_country()
    |> Enum.filter(&(&1 > 0))
    |> List.first(16)
  end

  @doc """
  Validates that a VAT rate is allowed for a given country on a changeset.

  ## Usage in changesets

      changeset
      |> VatRates.validate_rate(:vat_rate, "KZ")

  """
  @spec validate_rate(Ecto.Changeset.t(), atom(), country_code()) :: Ecto.Changeset.t()
  def validate_rate(changeset, field, country_code \\ @default_country) do
    allowed_rates = for_country(country_code)

    validate_inclusion(changeset, field, allowed_rates,
      message: "must be one of: #{Enum.join(allowed_rates, ", ")}% for country #{country_code}"
    )
  end

  @doc """
  Checks if a VAT rate is valid for a given country.

  ## Examples

      iex> EdocApi.VatRates.valid_rate?(16, "KZ")
      true

      iex> EdocApi.VatRates.valid_rate?(12, "KZ")
      false

      iex> EdocApi.VatRates.valid_rate?(0, "KZ")
      true

  """
  @spec valid_rate?(vat_rate(), country_code()) :: boolean()
  def valid_rate?(rate, country_code \\ @default_country) do
    rate in for_country(country_code)
  end

  @doc """
  Returns all configured country codes.

  ## Examples

      iex> EdocApi.VatRates.configured_countries()
      ["KZ", "RU", "DEFAULT"]

  """
  @spec configured_countries() :: [country_code()]
  def configured_countries do
    Map.keys(@rates)
  end

  @doc """
  Returns the default country code.

  ## Examples

      iex> EdocApi.VatRates.default_country()
      "KZ"

  """
  @spec default_country() :: country_code()
  def default_country, do: @default_country

  @doc """
  Calculates VAT amount from subtotal and rate, using currency-specific precision.

  ## Examples

      iex> VatRates.calculate_vat(Decimal.new("1000"), 16, "KZ")
      #Decimal<160.00>

  """
  @spec calculate_vat(Decimal.t(), vat_rate(), String.t()) :: Decimal.t()
  def calculate_vat(subtotal, rate, currency_code \\ "KZT") do
    subtotal
    |> Decimal.mult(Decimal.new(rate))
    |> Decimal.div(Decimal.new(100))
    |> apply_currency_precision(currency_code)
  end

  @doc """
  Calculates total from subtotal and VAT, using currency-specific precision.

  ## Examples

      iex> VatRates.calculate_total(Decimal.new("1000"), Decimal.new("160"), "KZT")
      #Decimal<1160.00>

  """
  @spec calculate_total(Decimal.t(), Decimal.t(), String.t()) :: Decimal.t()
  def calculate_total(subtotal, vat, currency_code \\ "KZT") do
    subtotal
    |> Decimal.add(vat)
    |> apply_currency_precision(currency_code)
  end

  # Private helpers

  defp normalize_country_code(country_code) when is_binary(country_code) do
    country_code |> String.trim() |> String.upcase()
  end

  defp apply_currency_precision(%Decimal{} = decimal, currency_code) do
    # Use Currencies module for precision if available
    if Code.ensure_loaded?(EdocApi.Currencies) do
      apply(EdocApi.Currencies, :round_currency, [decimal, currency_code])
    else
      # Fallback to 2 decimal places
      Decimal.round(decimal, 2)
    end
  end

  defp apply_currency_precision(decimal, _currency_code), do: decimal
end
