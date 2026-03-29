defmodule EdocApi.BuyersTest do
  use EdocApi.DataCase

  alias EdocApi.Buyers
  alias EdocApi.Core.Bank
  alias EdocApi.Repo
  import EdocApi.TestFixtures

  describe "buyer bank account integration" do
    test "create_buyer_for_company/2 creates default buyer bank account" do
      user = create_user!()
      company = create_company!(user)
      bank = create_bank!()

      attrs = %{
        "name" => "Buyer One",
        "bin_iin" => "060215385673",
        "bank_id" => bank.id,
        "iban" => "KZ770000000000000001",
        "bic" => "BICABC12"
      }

      assert {:ok, buyer} = Buyers.create_buyer_for_company(company.id, attrs)
      assert length(buyer.bank_accounts) == 1

      account = hd(buyer.bank_accounts)
      assert account.is_default
      assert account.bank_id == bank.id
      assert account.iban == "KZ770000000000000001"
      assert account.bic == "BICABC12"
    end

    test "update_buyer/3 updates default buyer bank account" do
      user = create_user!()
      company = create_company!(user)
      bank1 = create_bank!()
      bank2 = create_bank!()

      assert {:ok, buyer} =
               Buyers.create_buyer_for_company(company.id, %{
                 "name" => "Buyer Two",
                 "bin_iin" => "090215385679",
                 "bank_id" => bank1.id,
                 "iban" => "KZ500000000000000002"
               })

      assert {:ok, updated_buyer} =
               Buyers.update_buyer(
                 buyer.id,
                 %{
                   "name" => "Buyer Two Updated",
                   "bin_iin" => "090215385679",
                   "bank_id" => bank2.id,
                   "iban" => "KZ230000000000000003",
                   "bic" => "NEWSWFT1"
                 },
                 company.id
               )

      assert updated_buyer.name == ~s("Buyer Two Updated")
      assert length(updated_buyer.bank_accounts) == 1

      account = hd(updated_buyer.bank_accounts)
      assert account.bank_id == bank2.id
      assert account.iban == "KZ230000000000000003"
      assert account.bic == "NEWSWFT1"
      assert account.is_default
    end
  end

  defp create_bank! do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    bic = "BIC#{String.slice(suffix, 0, 8)}"
    Repo.insert!(%Bank{name: "Buyer Test Bank #{suffix}", bic: bic})
  end
end
