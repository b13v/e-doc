defmodule EdocApiWeb.CompanyControllerTest do
  use EdocApiWeb.ConnCase

  alias EdocApi.Accounts
  alias EdocApi.Billing
  alias EdocApi.Core.TenantMembership
  alias EdocApi.Repo
  alias EdocApi.TeamMemberships

  import EdocApi.TestFixtures

  setup %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, conn: authenticate(conn, user), user: user, company: company}
  end

  describe "update_subscription/2" do
    test "returns gone and does not mutate billing plan through API", %{
      conn: conn,
      company: company
    } do
      {:ok, _plans} = Billing.seed_default_plans()
      {:ok, subscription} = Billing.create_trial_subscription(company)
      {:ok, _basic} = Billing.activate_subscription(subscription, "basic")

      conn = put(conn, "/v1/company/subscription", %{"plan" => "basic"})

      body = json_response(conn, 410)

      assert body["error"] == "subscription_mutation_retired"
      assert body["message"] == "Subscription changes are managed on /company/billing."
      assert {:ok, current} = Billing.get_current_subscription(company.id)
      assert current.plan.code == "basic"
    end

    test "retired API does not run downgrade validation or mutate seats", %{
      conn: conn,
      company: company
    } do
      {:ok, _plans} = Billing.seed_default_plans()
      {:ok, subscription} = Billing.create_trial_subscription(company)
      {:ok, _basic} = Billing.activate_subscription(subscription, "basic")

      {:ok, _first} =
        TeamMemberships.invite_member(company.id, %{
          "email" => "first-api@example.com",
          "role" => "member"
        })

      {:ok, _second} =
        TeamMemberships.invite_member(company.id, %{
          "email" => "second-api@example.com",
          "role" => "member"
        })

      conn = put(conn, "/v1/company/subscription", %{"plan" => "starter"})
      body = json_response(conn, 410)

      assert body["error"] == "subscription_mutation_retired"
      assert {:ok, current} = Billing.get_current_subscription(company.id)
      assert current.plan.code == "basic"
    end
  end

  describe "role guards" do
    setup %{conn: conn} do
      owner = create_user!()
      Accounts.mark_email_verified!(owner.id)
      company = create_company!(owner)

      {:ok, _plans} = Billing.seed_default_plans()
      {:ok, subscription} = Billing.create_trial_subscription(company)
      {:ok, _sub} = Billing.activate_subscription(subscription, "basic")

      member_user = create_user!(%{"email" => "api-member-role@example.com"})
      admin_user = create_user!(%{"email" => "api-admin-role@example.com"})

      Accounts.mark_email_verified!(member_user.id)
      Accounts.mark_email_verified!(admin_user.id)

      {:ok, _member_invite} =
        TeamMemberships.invite_member(company.id, %{
          "email" => member_user.email,
          "role" => "member"
        })

      {:ok, _admin_invite} =
        TeamMemberships.invite_member(company.id, %{
          "email" => admin_user.email,
          "role" => "member"
        })

      [member_membership_id] = TeamMemberships.accept_pending_memberships_for_user(member_user)
      [admin_membership_id] = TeamMemberships.accept_pending_memberships_for_user(admin_user)

      admin_membership = Repo.get!(TenantMembership, admin_membership_id)

      {:ok, _updated_admin} =
        admin_membership
        |> Ecto.Changeset.change(role: "admin")
        |> Repo.update()

      {:ok,
       member_conn: authenticate(conn, member_user),
       admin_conn: authenticate(conn, admin_user),
       company: company,
       member_membership_id: member_membership_id}
    end

    test "member gets 403 on PUT /v1/company/subscription", %{
      member_conn: conn,
      company: company
    } do
      conn = put(conn, "/v1/company/subscription", %{"plan" => "basic"})

      body = json_response(conn, 410)

      assert body["error"] == "subscription_mutation_retired"
      assert {:ok, current} = Billing.get_current_subscription(company.id)
      assert current.plan.code == "basic"
    end

    test "admin also receives retired API response on PUT /v1/company/subscription", %{
      admin_conn: conn,
      company: company
    } do
      conn = put(conn, "/v1/company/subscription", %{"plan" => "basic"})

      body = json_response(conn, 410)

      assert body["error"] == "subscription_mutation_retired"
      assert {:ok, current} = Billing.get_current_subscription(company.id)
      assert current.plan.code == "basic"
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = EdocApi.Auth.Token.generate_access_token(user.id)
    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
