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

  test "effective seat limit includes add-on seats" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "included_document_limit" => 50,
        "included_seat_limit" => 2,
        "add_on_seat_quantity" => 3
      })

    assert Monetization.effective_seat_limit(company.id) == 5
  end

  test "subscription_snapshot reports plan, usage, and seat counts" do
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
             seat_limit: 7
           } = Monetization.subscription_snapshot(company.id)
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
end
