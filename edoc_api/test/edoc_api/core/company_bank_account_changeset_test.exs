defmodule EdocApi.Core.CompanyBankAccountChangesetTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Core.CompanyBankAccount

  test "accepts exactly 20-char IBAN" do
    company_id = Ecto.UUID.generate()

    attrs = %{
      "label" => "Main",
      "iban" => "KZ770000000000000001",
      "bank_id" => Ecto.UUID.generate(),
      "kbe_code_id" => Ecto.UUID.generate(),
      "knp_code_id" => Ecto.UUID.generate()
    }

    changeset = CompanyBankAccount.changeset(%CompanyBankAccount{}, attrs, company_id)
    assert changeset.valid?
  end

  test "rejects IBAN shorter than 20 chars" do
    company_id = Ecto.UUID.generate()

    attrs = %{
      "label" => "Main",
      "iban" => "KZ00000000000000001",
      "bank_id" => Ecto.UUID.generate(),
      "kbe_code_id" => Ecto.UUID.generate(),
      "knp_code_id" => Ecto.UUID.generate()
    }

    changeset = CompanyBankAccount.changeset(%CompanyBankAccount{}, attrs, company_id)
    refute changeset.valid?
    assert {"has invalid checksum", _} = Keyword.fetch!(changeset.errors, :iban)
  end
end
