defmodule EdocApi.LegalFormsTest do
  use ExUnit.Case, async: true

  alias EdocApi.Core.Buyer
  alias EdocApi.Core.Company
  alias EdocApi.LegalForms

  describe "normalize/1" do
    test "maps short forms to full names" do
      assert LegalForms.normalize("ТОО") == "Товарищество с ограниченной ответственностью"
      assert LegalForms.normalize("АО") == "Акционерное общество"
      assert LegalForms.normalize("ИП") == "Индивидуальный предприниматель"
    end
  end

  describe "schema validation" do
    test "buyer changeset accepts short legal form and normalizes it" do
      attrs = %{
        "name" => "Buyer Test",
        "bin_iin" => "060215385673",
        "legal_form" => "ТОО"
      }

      changeset = Buyer.changeset(%Buyer{}, attrs, Ecto.UUID.generate())

      assert changeset.valid?

      assert Ecto.Changeset.get_field(changeset, :legal_form) ==
               "Товарищество с ограниченной ответственностью"
    end

    test "company changeset rejects unsupported legal form" do
      attrs = %{
        "name" => "Company Test",
        "legal_form" => "ГКП",
        "bin_iin" => "060215385673",
        "city" => "Астана",
        "address" => "Address",
        "phone" => "+7 (777) 123 45 67",
        "representative_name" => "Director",
        "representative_title" => "Director",
        "basis" => "Устав"
      }

      changeset = Company.changeset(%Company{}, attrs, Ecto.UUID.generate())

      refute changeset.valid?
      assert {"is invalid", _opts} = Keyword.fetch!(changeset.errors, :legal_form)
    end
  end
end
