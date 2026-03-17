defmodule EdocApi.ActsTest do
  use EdocApi.DataCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Acts
  alias EdocApi.Buyers
  alias EdocApi.Repo

  describe "create_act_for_user/3" do
    test "creates draft act with items for valid buyer" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)

      attrs = %{
        "issue_date" => Date.utc_today(),
        "buyer_id" => buyer.id,
        "buyer_address" => "Buyer Address",
        "items" => [
          %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
        ]
      }

      assert {:ok, act} = Acts.create_act_for_user(user.id, company.id, attrs)
      assert act.status == "draft"
      assert length(act.items) == 1
      assert Enum.at(act.items, 0).name == "Services"
    end
  end

  describe "delete_act_for_user/2" do
    test "returns business rule error for non-draft acts" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)

      attrs = %{
        "issue_date" => Date.utc_today(),
        "buyer_id" => buyer.id,
        "buyer_address" => "Buyer Address",
        "items" => [
          %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
        ]
      }

      assert {:ok, act} = Acts.create_act_for_user(user.id, company.id, attrs)

      act
      |> Ecto.Changeset.change(status: "issued")
      |> Repo.update!()

      assert {:error, :business_rule, %{rule: :cannot_delete_non_draft_act}} =
               Acts.delete_act_for_user(user.id, act.id)
    end
  end

  defp create_buyer!(company) do
    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    buyer
  end
end
