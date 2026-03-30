defmodule EdocApi.Validators.BinIinTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias EdocApi.Validators.BinIin

  test "accepts valid checksum" do
    changeset =
      {%{}, %{bin_iin: :string}}
      |> Changeset.cast(%{bin_iin: "060215385673"}, [:bin_iin])
      |> BinIin.validate(:bin_iin)

    assert changeset.valid?
  end

  test "rejects invalid checksum" do
    changeset =
      {%{}, %{bin_iin: :string}}
      |> Changeset.cast(%{bin_iin: "060215385679"}, [:bin_iin])
      |> BinIin.validate(:bin_iin)

    refute changeset.valid?
    assert {"has invalid checksum", _} = Keyword.fetch!(changeset.errors, :bin_iin)
  end
end
