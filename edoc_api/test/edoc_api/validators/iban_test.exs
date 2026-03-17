defmodule EdocApi.Validators.IbanTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias EdocApi.Validators.Iban

  test "accepts valid IBAN checksum" do
    changeset =
      {%{}, %{iban: :string}}
      |> Changeset.cast(%{iban: "KZ971234567890123456"}, [:iban])
      |> Iban.validate(:iban)

    assert changeset.valid?
  end

  test "rejects invalid IBAN checksum" do
    changeset =
      {%{}, %{iban: :string}}
      |> Changeset.cast(%{iban: "KZ961234567890123456"}, [:iban])
      |> Iban.validate(:iban)

    refute changeset.valid?
    assert {"has invalid checksum", _} = Keyword.fetch!(changeset.errors, :iban)
  end
end
