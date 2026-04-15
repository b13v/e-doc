defmodule EdocApi.Documents.Builders.ContractDataBuilderTest do
  use EdocApi.DataCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Buyers
  alias EdocApi.Core
  alias EdocApi.Documents.Builders.ContractDataBuilder

  test "builds seller and buyer titles from company and buyer records" do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)

    company =
      create_company!(user, %{
        "city" => "Шымкент",
        "representative_name" => "Айдар Сатпаев",
        "representative_title" => "Генеральный директор"
      })

    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Buyer With Title",
        "bin_iin" => "101215385676",
        "city" => "Караганда",
        "address" => "Buyer Address",
        "director_name" => "Мария Ким",
        "director_title" => "Коммерческий директор",
        "basis" => "Доверенности"
      })

    contract =
      create_contract!(company, %{
        "number" => "CON-BUILDER-TITLE",
        "buyer_id" => buyer.id,
        "city" => nil
      })

    {:ok, contract} = Core.get_contract_for_user(user.id, contract.id)

    seller = ContractDataBuilder.build_seller_data(contract)
    buyer_data = ContractDataBuilder.build_buyer_data(contract)

    assert seller.city == "Шымкент"
    assert seller.address_line == "г. Шымкент, Some Street 1"
    assert seller.director_title == "Генеральный директор"
    assert buyer_data.city == "Караганда"
    assert buyer_data.address_line == "г. Караганда, Buyer Address"
    assert buyer_data.director_title == "Коммерческий директор"
  end

  test "keeps legacy contract city and buyer title fallbacks when associations are absent" do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)

    company = create_company!(user)

    contract =
      create_contract!(company, %{
        "number" => "CON-BUILDER-LEGACY",
        "city" => "Астана",
        "buyer_name" => "Legacy Buyer",
        "buyer_director_title" => "Руководитель",
        "buyer_director_name" => "Legacy Director"
      })

    seller = ContractDataBuilder.build_seller_data(contract)
    buyer_data = ContractDataBuilder.build_buyer_data(contract)

    assert seller.city == "Астана"
    assert seller.address_line == "г. Астана, Some Street 1"
    assert seller.director_title == "директор"
    assert buyer_data.address_line == "Test Buyer Address"
    assert buyer_data.director_title == "Руководитель"
    assert buyer_data.director_name == "Legacy Director"
  end
end
