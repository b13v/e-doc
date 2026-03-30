defmodule EdocApi.PaymentsTest do
  use EdocApi.DataCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Payments
  alias EdocApi.Core.CompanyBankAccount
  alias EdocApi.Repo

  describe "create_company_bank_account_for_user/2" do
    test "returns company_required when user has no company" do
      user = create_user!()

      assert {:error, :company_required} =
               Payments.create_company_bank_account_for_user(user.id, %{
                 "label" => "Main",
                 "iban" => valid_kz_iban(123),
                 "bank_id" => Ecto.UUID.generate()
               })
    end
  end

  describe "set_default_bank_account/2" do
    test "switches default account within the same company" do
      user = create_user!()
      company = create_company!(user)

      account_a = create_company_bank_account!(company, %{"label" => "A", "is_default" => true})
      account_b = create_company_bank_account!(company, %{"label" => "B", "is_default" => false})

      assert {:ok, updated} = Payments.set_default_bank_account(user.id, account_b.id)
      assert updated.id == account_b.id
      assert updated.is_default == true

      reloaded_a = Repo.get!(CompanyBankAccount, account_a.id)
      reloaded_b = Repo.get!(CompanyBankAccount, account_b.id)

      assert reloaded_a.is_default == false
      assert reloaded_b.is_default == true
    end

    test "does not allow setting default for another company account" do
      user = create_user!()
      _company = create_company!(user)

      other_user = create_user!()
      other_company = create_company!(other_user)
      other_account = create_company_bank_account!(other_company)

      assert {:error, :bank_account_not_found} =
               Payments.set_default_bank_account(user.id, other_account.id)
    end
  end
end
