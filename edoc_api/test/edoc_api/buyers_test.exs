defmodule EdocApi.BuyersTest do
  use EdocApi.DataCase
  import Ecto.Query, only: [from: 2]

  alias EdocApi.Buyers
  alias EdocApi.Core.Bank
  alias EdocApi.Core.BuyerBankAccount
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

    test "get_default_bank_account/1 prefers the default account even when newer non-default exists" do
      user = create_user!()
      company = create_company!(user)
      default_bank = create_bank!()
      fallback_bank = create_bank!()

      assert {:ok, buyer} =
               Buyers.create_buyer_for_company(company.id, %{
                 "name" => "Buyer Default Preference",
                 "bin_iin" => "060215385673",
                 "bank_id" => default_bank.id,
                 "iban" => "KZ770000000000000001",
                 "bic" => "DEFKBIC1"
               })

      # Insert newer non-default account.
      %BuyerBankAccount{}
      |> BuyerBankAccount.changeset(
        %{
          "bank_id" => fallback_bank.id,
          "iban" => "KZ500000000000000002",
          "bic" => "FALLBIC2",
          "is_default" => false
        },
        buyer.id
      )
      |> Repo.insert!()

      account = Buyers.get_default_bank_account(buyer.id)
      assert account.is_default
      assert account.iban == "KZ770000000000000001"
    end

    test "get_default_bank_account/1 falls back to the latest account when none is default" do
      user = create_user!()
      company = create_company!(user)
      first_bank = create_bank!()
      latest_bank = create_bank!()

      assert {:ok, buyer} =
               Buyers.create_buyer_for_company(company.id, %{
                 "name" => "Buyer Latest Fallback",
                 "bin_iin" => "090215385679",
                 "bank_id" => first_bank.id,
                 "iban" => "KZ230000000000000003",
                 "bic" => "FIRSBIC3"
               })

      newer_account =
        %BuyerBankAccount{}
        |> BuyerBankAccount.changeset(
          %{
            "bank_id" => latest_bank.id,
            "iban" => "KZ500000000000000002",
            "bic" => "LATSBIC4",
            "is_default" => false
          },
          buyer.id
        )
        |> Repo.insert!()

      from(a in BuyerBankAccount, where: a.buyer_id == ^buyer.id)
      |> Repo.update_all(set: [is_default: false])

      from(a in BuyerBankAccount, where: a.id == ^newer_account.id)
      |> Repo.update_all(set: [inserted_at: DateTime.utc_now() |> DateTime.add(1, :second)])

      account = Buyers.get_default_bank_account(buyer.id)
      refute account.is_default
      assert account.iban == "KZ500000000000000002"
    end
  end

  defp create_bank! do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    bic = "BIC#{String.slice(suffix, 0, 8)}"
    Repo.insert!(%Bank{name: "Buyer Test Bank #{suffix}", bic: bic})
  end
end
