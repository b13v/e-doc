defmodule EdocApiWeb.SessionControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Companies
  alias EdocApi.Monetization

  test "html login activates invited memberships", %{conn: conn} do
    owner = create_user!()
    Accounts.mark_email_verified!(owner.id)
    company = create_company!(owner)

    invited = create_user!(%{"email" => "invitee2@example.com"})
    Accounts.mark_email_verified!(invited.id)

    assert {:ok, _membership} =
             Monetization.invite_member(company.id, %{
               "email" => invited.email,
               "role" => "member"
             })

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> post("/login", %{"email" => invited.email, "password" => "password123"})

    assert redirected_to(conn) == "/company"
    assert get_session(conn, :user_id) == invited.id
    assert Companies.get_company_by_user_id(invited.id).id == company.id
  end
end
