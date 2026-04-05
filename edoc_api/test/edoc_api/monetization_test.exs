defmodule EdocApi.MonetizationTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Monetization
  import EdocApi.TestFixtures

  test "creates a trial subscription lazily on first quota consumption" do
    user = create_user!()
    company = create_company!(user)

    assert {:ok, %{used: 1, limit: 10, remaining: 9}} =
             Monetization.consume_document_quota(
               company.id,
               "invoice",
               Ecto.UUID.generate(),
               "invoice_issued"
             )
  end

  test "rejects quota consumption after limit is exceeded" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "included_document_limit" => 1,
        "included_seat_limit" => 2
      })

    assert {:ok, %{used: 1, limit: 1, remaining: 0}} =
             Monetization.consume_document_quota(
               company.id,
               "invoice",
               Ecto.UUID.generate(),
               "invoice_issued"
             )

    assert {:error, :quota_exceeded, %{used: 1, limit: 1}} =
             Monetization.consume_document_quota(
               company.id,
               "invoice",
               Ecto.UUID.generate(),
               "invoice_issued"
             )
  end

  test "effective seat limit ignores legacy add-on seats and uses fixed plan limits" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "included_document_limit" => 50,
        "included_seat_limit" => 2,
        "add_on_seat_quantity" => 3
      })

    assert Monetization.effective_seat_limit(company.id) == 2
  end

  test "subscription_snapshot reports plan, usage, and fixed seat counts" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "basic",
        "included_document_limit" => 500,
        "included_seat_limit" => 5,
        "add_on_seat_quantity" => 2
      })

    assert {:ok, %{used: 1, limit: 500, remaining: 499}} =
             Monetization.consume_document_quota(
               company.id,
               "invoice",
               Ecto.UUID.generate(),
               "invoice_issued"
             )

    assert %{
             plan: "basic",
             documents_used: 1,
             document_limit: 500,
             seats_used: 1,
             seat_limit: 5
           } = Monetization.subscription_snapshot(company.id)
  end

  test "validate_plan_change/2 blocks downgrade when occupied seats exceed starter limit" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "basic"
      })

    assert {:ok, _membership} =
             Monetization.invite_member(company.id, %{
               "email" => "first@example.com",
               "role" => "member"
             })

    assert {:ok, _membership} =
             Monetization.invite_member(company.id, %{
               "email" => "second@example.com",
               "role" => "member"
             })

    assert {:error, :seat_limit_exceeded_on_downgrade,
            %{
              plan: "starter",
              seat_limit: 2,
              seats_used: 3,
              seats_to_remove: 1,
              blocking_memberships: [_]
            }} = Monetization.validate_plan_change(company.id, "starter")
  end

  test "validate_plan_change/2 suggests invited memberships before active ones" do
    user = create_user!()
    company = create_company!(user)
    active_user = create_user!()
    another_active_user = create_user!()

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "basic"
      })

    Monetization.ensure_owner_membership(company.id, active_user.id)
    Monetization.ensure_owner_membership(company.id, another_active_user.id)

    assert {:ok, invited_membership} =
             Monetization.invite_member(company.id, %{
               "email" => "invite-first@example.com",
               "role" => "member"
             })

    active_memberships =
      Monetization.list_memberships(company.id)
      |> Enum.filter(&(&1.status == "active"))

    admin_membership = Enum.find(active_memberships, &(&1.user_id == active_user.id))
    extra_owner_membership = Enum.find(active_memberships, &(&1.user_id == another_active_user.id))

    {:ok, _updated_admin} =
      admin_membership
      |> Ecto.Changeset.change(role: "admin")
      |> EdocApi.Repo.update()

    assert {:error, :seat_limit_exceeded_on_downgrade, %{blocking_memberships: blocking}} =
             Monetization.validate_plan_change(company.id, "starter")

    assert extra_owner_membership.role == "owner"
    assert Enum.map(blocking, & &1.id) == [invited_membership.id, admin_membership.id]
  end

  test "validate_plan_change/2 allows downgrade when occupied seats fit the target plan" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "basic"
      })

    assert {:ok, %{plan: "starter", seat_limit: 2}} =
             Monetization.validate_plan_change(company.id, "starter")
  end

  test "invite_member/2 creates an invited membership with normalized email" do
    user = create_user!()
    company = create_company!(user)

    assert {:ok, membership} =
             Monetization.invite_member(company.id, %{
               "email" => " Teammate@Example.com ",
               "role" => "member"
             })

    assert membership.status == "invited"
    assert membership.user_id == nil
    assert membership.invite_email == "teammate@example.com"
  end

  test "invite_member/2 rejects invite when all seats are occupied" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "included_seat_limit" => 2
      })

    assert {:ok, _membership} =
             Monetization.invite_member(company.id, %{
               "email" => "one@example.com",
               "role" => "member"
             })

    assert {:error, :seat_limit_reached, %{limit: 2}} =
             Monetization.invite_member(company.id, %{
               "email" => "two@example.com",
               "role" => "member"
             })
  end

  test "invite_member/2 rejects duplicate invited email within the same company" do
    user = create_user!()
    company = create_company!(user)

    assert {:ok, _membership} =
             Monetization.invite_member(company.id, %{
               "email" => "dup@example.com",
               "role" => "member"
             })

    assert {:error, :duplicate_invite, %{email: "dup@example.com"}} =
             Monetization.invite_member(company.id, %{
               "email" => " DUP@example.com ",
               "role" => "member"
             })
  end

  test "invite_member/2 rejects email that already belongs to an active member" do
    user = create_user!()
    company = create_company!(user)

    assert {:error, :duplicate_member, %{email: email}} =
             Monetization.invite_member(company.id, %{
               "email" => user.email,
               "role" => "member"
             })

    assert email == user.email
  end

  test "subscription_snapshot counts invited memberships as occupied seats" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "included_seat_limit" => 2
      })

    assert {:ok, _membership} =
             Monetization.invite_member(company.id, %{
               "email" => "seat@example.com",
               "role" => "member"
             })

    assert %{seats_used: 2, seat_limit: 2} = Monetization.subscription_snapshot(company.id)
  end

  test "remove_membership/2 marks invited membership as removed and frees the seat" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "included_seat_limit" => 2
      })

    assert {:ok, membership} =
             Monetization.invite_member(company.id, %{
               "email" => "remove@example.com",
               "role" => "member"
             })

    assert %{seats_used: 2} = Monetization.subscription_snapshot(company.id)

    assert {:ok, removed_membership} = Monetization.remove_membership(company.id, membership.id)
    assert removed_membership.status == "removed"
    assert %{seats_used: 1} = Monetization.subscription_snapshot(company.id)
  end

  test "remove_membership/2 rejects removing the only owner" do
    user = create_user!()
    company = create_company!(user)

    owner_membership = Monetization.list_memberships(company.id) |> Enum.find(&(&1.role == "owner"))

    assert {:error, :last_owner} =
             Monetization.remove_membership(company.id, owner_membership.id)
  end

  test "accept_pending_memberships_for_user/1 marks invite as pending_seat when no seats are available and activates later" do
    owner = create_user!()
    company = create_company!(owner)
    first_user = create_user!(%{"email" => "first-seat@example.com"})
    second_user = create_user!(%{"email" => "second-seat@example.com"})

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "basic"
      })

    assert {:ok, first_membership} =
             Monetization.invite_member(company.id, %{
               "email" => first_user.email,
               "role" => "member"
             })

    assert {:ok, second_membership} =
             Monetization.invite_member(company.id, %{
               "email" => second_user.email,
               "role" => "member"
             })

    first_membership_id = first_membership.id
    second_membership_id = second_membership.id

    assert [^first_membership_id] = Monetization.accept_pending_memberships_for_user(first_user)

    {:ok, _starter_sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter"
      })

    assert [] = Monetization.accept_pending_memberships_for_user(second_user)

    pending =
      Monetization.list_memberships(company.id)
      |> Enum.find(&(&1.id == second_membership_id))

    assert pending.status == "pending_seat"

    assert {:ok, _removed} = Monetization.remove_membership(company.id, first_membership.id)
    assert [^second_membership_id] = Monetization.accept_pending_memberships_for_user(second_user)

    activated =
      Monetization.list_memberships(company.id)
      |> Enum.find(&(&1.id == second_membership_id))

    assert activated.status == "active"
    assert activated.user_id == second_user.id
    assert activated.invite_email == nil
  end
end
