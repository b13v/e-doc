defmodule EdocApi.ActsTest do
  use EdocApi.DataCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Acts
  alias EdocApi.ActStatus
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

  describe "sign_act_for_user/2" do
    test "marks an issued act as signed" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)
      act = create_act!(user, company, buyer, ActStatus.issued())

      assert {:ok, signed} = Acts.sign_act_for_user(user.id, act.id)
      assert signed.status == ActStatus.signed()
    end

    test "returns business rule error for draft acts" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)
      act = create_act!(user, company, buyer, ActStatus.draft())

      assert {:error, :business_rule, %{rule: :act_not_issued}} =
               Acts.sign_act_for_user(user.id, act.id)
    end

    test "returns business rule error for already signed acts" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)
      act = create_act!(user, company, buyer, ActStatus.signed())

      assert {:error, :business_rule, %{rule: :act_already_signed}} =
               Acts.sign_act_for_user(user.id, act.id)
    end
  end

  describe "issue_act_for_user/2" do
    test "marks a draft act as issued" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)
      act = create_act!(user, company, buyer, ActStatus.draft())

      assert {:ok, issued} = Acts.issue_act_for_user(user.id, act.id)
      assert issued.status == ActStatus.issued()
    end

    test "returns business rule error for non-draft acts" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)
      act = create_act!(user, company, buyer, ActStatus.issued())

      assert {:error, :business_rule, %{rule: :act_not_editable}} =
               Acts.issue_act_for_user(user.id, act.id)
    end

    test "returns business rule error when monthly document quota is exceeded" do
      user = create_user!()
      company = create_company!(user)
      buyer = create_buyer!(company)

      {:ok, _sub} =
        EdocApi.Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "starter",
          "included_document_limit" => 1,
          "included_seat_limit" => 2
        })

      act_1 = create_act!(user, company, buyer, ActStatus.draft())
      act_2 = create_act!(user, company, buyer, ActStatus.draft())

      assert {:ok, issued} = Acts.issue_act_for_user(user.id, act_1.id)
      assert issued.status == ActStatus.issued()

      assert {:error, :business_rule, %{rule: :quota_exceeded, details: %{used: 1, limit: 1}}} =
               Acts.issue_act_for_user(user.id, act_2.id)
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

  defp create_act!(user, company, buyer, status) do
    attrs = %{
      "issue_date" => Date.utc_today(),
      "buyer_id" => buyer.id,
      "buyer_address" => "Buyer Address",
      "items" => [
        %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
      ]
    }

    {:ok, act} = Acts.create_act_for_user(user.id, company.id, attrs)

    act
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end
end
