defmodule EdocApi.CompaniesTest do
  use EdocApi.DataCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Companies

  describe "upsert_company_for_user/2" do
    test "updates existing company for the same user" do
      user = create_user!()

      company = create_company!(user, %{"name" => "Initial Company"})
      updated = create_company!(user, %{"name" => "Updated Company"})

      assert updated.id == company.id
      assert updated.name == "Updated Company"
      assert Companies.get_company_by_user_id(user.id).id == company.id
    end
  end

  describe "get_company_by_user_id/1" do
    test "returns nil when user has no company" do
      user = create_user!()

      assert Companies.get_company_by_user_id(user.id) == nil
    end
  end
end
