defmodule EdocApi.CurrenciesTest do
  use EdocApi.DataCase

  alias EdocApi.Currencies

  describe "supported_currencies/0" do
    test "returns only KZT" do
      assert Currencies.supported_currencies() == ["KZT"]
    end
  end

  describe "supported?/1" do
    test "returns true for KZT" do
      assert Currencies.supported?("KZT") == true
      assert Currencies.supported?(:KZT) == true
    end

    test "returns false for other currencies" do
      assert Currencies.supported?("USD") == false
      assert Currencies.supported?("EUR") == false
      assert Currencies.supported?("RUB") == false
      assert Currencies.supported?("GBP") == false
    end
  end

  describe "precision/1" do
    test "returns correct precision for KZT" do
      assert Currencies.precision("KZT") == 2
      assert Currencies.precision(:KZT) == 2
    end

    test "returns default precision for any currency (only KZT supported)" do
      # Since we only support KZT, all precision calls return 2 (KZT precision)
      assert Currencies.precision("USD") == 2
      assert Currencies.precision("EUR") == 2
      assert Currencies.precision("GBP") == 2
      assert Currencies.precision("UNKNOWN") == 2
    end
  end

  describe "round_currency/2" do
    test "rounds KZT to 2 decimal places" do
      assert Currencies.round_currency(Decimal.new("123.456"), "KZT") == Decimal.new("123.46")
      assert Currencies.round_currency(Decimal.new("123.454"), "KZT") == Decimal.new("123.45")
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
