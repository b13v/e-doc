defmodule EdocApi.TestFixturesTest do
  use ExUnit.Case, async: true

  import EdocApi.TestFixtures

  test "bank_bic_for_suffix/1 stays unique and valid for large suffixes" do
    bic_a = bank_bic_for_suffix(1_000_000_002)
    bic_b = bank_bic_for_suffix(1_000_000_066)

    assert bic_a != bic_b
    assert bic_a =~ ~r/^[A-Z0-9]{6,11}$/
    assert bic_b =~ ~r/^[A-Z0-9]{6,11}$/
  end

  test "unique_email/0 is not based only on a small monotonic integer" do
    email = unique_email()

    refute email =~ ~r/^user\d+@example\.com$/
  end
end
