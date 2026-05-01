defmodule EdocApi.TeamMembershipsTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Accounts
  alias EdocApi.Core.TenantMembership
  alias EdocApi.Repo
  alias EdocApi.TeamMemberships

  import EdocApi.TestFixtures

  test "invite_member/2 creates an invited membership with normalized email" do
    user = create_user!()
    company = create_company!(user)

    assert {:ok, membership} =
             TeamMemberships.invite_member(company.id, %{
               "email" => " Member@Example.COM ",
               "role" => "admin"
             })

    assert membership.invite_email == "member@example.com"
    assert membership.role == "admin"
    assert membership.status == "invited"
  end

  test "invite_member/2 rejects invite when all seats are occupied" do
    user = create_user!()
    company = create_company!(user)
    activate_billing_plan!(company, "starter")

    assert {:ok, _first} =
             TeamMemberships.invite_member(company.id, %{
               "email" => "first@example.com",
               "role" => "member"
             })

    assert {:error, :seat_limit_reached, %{limit: 2}} =
             TeamMemberships.invite_member(company.id, %{
               "email" => "second@example.com",
               "role" => "member"
             })
  end

  test "accept_pending_memberships_for_user/1 marks invite as pending_seat and activates later" do
    owner = create_user!()
    company = create_company!(owner)
    activate_billing_plan!(company, "basic")

    first_user = create_user!(%{"email" => "first-pending@example.com"})
    second_user = create_user!(%{"email" => "second-pending@example.com"})
    Accounts.mark_email_verified!(first_user.id)
    Accounts.mark_email_verified!(second_user.id)

    {:ok, first_invite} =
      TeamMemberships.invite_member(company.id, %{
        "email" => first_user.email,
        "role" => "member"
      })

    {:ok, second_invite} =
      TeamMemberships.invite_member(company.id, %{
        "email" => second_user.email,
        "role" => "member"
      })

    assert [first_invite.id] == TeamMemberships.accept_pending_memberships_for_user(first_user)
    activate_billing_plan!(company, "starter")
    assert [] = TeamMemberships.accept_pending_memberships_for_user(second_user)
    assert Repo.get!(TenantMembership, second_invite.id).status == "pending_seat"
  end

  test "remove_membership/2 rejects removing the only owner" do
    owner = create_user!()
    company = create_company!(owner)

    owner_membership =
      TeamMemberships.list_memberships(company.id)
      |> Enum.find(&(&1.role == "owner"))

    assert {:error, :last_owner} =
             TeamMemberships.remove_membership(company.id, owner_membership.id)
  end

  test "remove_membership/2 deletes invited membership and frees the seat" do
    owner = create_user!()
    company = create_company!(owner)
    activate_billing_plan!(company, "starter")

    {:ok, invited} =
      TeamMemberships.invite_member(company.id, %{
        "email" => "invited-remove@example.com",
        "role" => "member"
      })

    assert {:error, :seat_limit_reached, _details} =
             TeamMemberships.invite_member(company.id, %{
               "email" => "blocked@example.com",
               "role" => "member"
             })

    assert {:ok, %{mode: :soft_removed_membership}} =
             TeamMemberships.remove_membership(company.id, invited.id)

    refute Repo.get(TenantMembership, invited.id)

    assert {:ok, replacement} =
             TeamMemberships.invite_member(company.id, %{
               "email" => "replacement@example.com",
               "role" => "member"
             })

    assert replacement.status == "invited"
  end
end
