defmodule EdocApi.CurrenciesTest do
  use EdocApi.DataCase

  alias EdocApi.Currencies

  describe "precision/1" do
    test "returns correct precision for KZT" do
      assert Currencies.precision("KZT") == 2
      assert Currencies.precision(:KZT) == 2
    end

    test "returns correct precision for USD" do
      assert Currencies.precision("USD") == 2
      assert Currencies.precision(:USD) == 2
    end

    test "returns correct precision for EUR" do
      assert Currencies.precision("EUR") == 2
      assert Currencies.precision(:EUR) == 2
    end

    test "returns correct precision for RUB" do
      assert Currencies.precision("RUB") == 2
      assert Currencies.precision(:RUB) == 2
    end

    test "returns correct precision for JPY (no decimal places)" do
      assert Currencies.precision("JPY") == 0
      assert Currencies.precision(:JPY) == 0
    end

    test "returns default precision for unknown currencies" do
      assert Currencies.precision("GBP") == 2
      assert Currencies.precision(:GBP) == 2
      assert Currencies.precision("UNKNOWN") == 2
    end
  end

  describe "round_currency/2" do
    test "rounds KZT to 2 decimal places" do
      assert Currencies.round_currency(Decimal.new("123.456"), "KZT") == Decimal.new("123.46")
      assert Currencies.round_currency(Decimal.new("123.454"), "KZT") == Decimal.new("123.45")
    end

    test "rounds USD to 2 decimal places" do
      assert Currencies.round_currency(Decimal.new("99.999"), "USD") == Decimal.new("100.00")
      assert Currencies.round_currency(Decimal.new("50.125"), "USD") == Decimal.new("50.13")
    end

    test "rounds JPY to 0 decimal places" do
      assert Currencies.round_currency(Decimal.new("123.456"), "JPY") == Decimal.new("123")
      assert Currencies.round_currency(Decimal.new("999.99"), "JPY") == Decimal.new("1000")
    end

    test "uses default precision when currency not specified" do
      assert Currencies.round_currency(Decimal.new("123.456")) == Decimal.new("123.46")
    end
  end

  describe "default_precision/0" do
    test "returns default precision" do
      assert Currencies.default_precision() == 2
    end
  end

  describe "round_default/1" do
    test "rounds using default precision" do
      assert Currencies.round_default(Decimal.new("123.456")) == Decimal.new("123.46")
      assert Currencies.round_default(Decimal.new("123.454")) == Decimal.new("123.45")
      assert Currencies.round_default(Decimal.new("0.005")) == Decimal.new("0.01")
    end

    test "handles whole numbers" do
      # Decimal.round normalizes to include precision
      assert Currencies.round_default(Decimal.new("123")) == Decimal.new("123.00")
    end
  end
end
