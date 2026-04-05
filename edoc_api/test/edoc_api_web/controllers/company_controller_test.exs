defmodule EdocApiWeb.CompanyControllerTest do
  use EdocApiWeb.ConnCase

  alias EdocApi.Accounts
  alias EdocApi.Monetization

  import EdocApi.TestFixtures

  setup %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, conn: authenticate(conn, user), user: user, company: company}
  end

  describe "update_subscription/2" do
    test "updates subscription plan through API", %{conn: conn, company: company} do
      conn = put(conn, "/v1/company/subscription", %{"plan" => "basic"})

      body = json_response(conn, 200)

      assert body["subscription"]["plan"] == "basic"
      assert body["subscription"]["seat_limit"] == 5
      assert Monetization.subscription_snapshot(company.id).plan == "basic"
    end

    test "blocks downgrade through API when occupied seats exceed starter limit", %{
      conn: conn,
      company: company
    } do
      {:ok, _sub} =
        Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "basic"
        })

      {:ok, _first} =
        Monetization.invite_member(company.id, %{
          "email" => "first-api@example.com",
          "role" => "member"
        })

      {:ok, _second} =
        Monetization.invite_member(company.id, %{
          "email" => "second-api@example.com",
          "role" => "member"
        })

      conn = put(conn, "/v1/company/subscription", %{"plan" => "starter"})
      body = json_response(conn, 422)

      assert body["error"] == "seat_limit_exceeded_on_downgrade"
      assert body["details"]["plan"] == "starter"
      assert body["details"]["seat_limit"] == 2
      assert body["details"]["seats_used"] == 3
      assert body["details"]["seats_to_remove"] == 1
      assert is_list(body["details"]["blocking_memberships"])
      assert Monetization.subscription_snapshot(company.id).plan == "basic"
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = EdocApi.Auth.Token.generate_access_token(user.id)
    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
