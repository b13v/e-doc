defmodule EdocApiWeb.ActsControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Acts
  alias EdocApi.Buyers
  alias EdocApi.Monetization

  setup %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put_private(:plug_skip_csrf_protection, true)
      |> put_req_header("accept", "text/html")

    {:ok, conn: conn, user: user, company: company}
  end

  describe "sign/2" do
    test "marks issued act as signed and redirects to the show page", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company, "issued")

      conn = post(conn, "/acts/#{act.id}/sign")

      assert redirected_to(conn) == "/acts/#{act.id}"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               Gettext.gettext(EdocApiWeb.Gettext, "Act marked as signed.")

      signed = Acts.get_act_for_user(user.id, act.id)
      assert signed.status == "signed"
    end

    test "rejects signing draft acts", %{conn: conn, user: user, company: company} do
      act = create_act!(user, company, "draft")

      conn = post(conn, "/acts/#{act.id}/sign")

      assert redirected_to(conn) == "/acts/#{act.id}"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               Gettext.gettext(
                 EdocApiWeb.Gettext,
                 "Only issued acts can be marked as signed."
               )
    end
  end

  describe "issue/2" do
    test "marks draft act as issued and redirects to the show page", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company, "draft")

      conn = post(conn, "/acts/#{act.id}/issue")

      assert redirected_to(conn) == "/acts/#{act.id}"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               Gettext.gettext(EdocApiWeb.Gettext, "Act issued successfully.")

      issued = Acts.get_act_for_user(user.id, act.id)
      assert issued.status == "issued"
    end

    test "rejects issuing non-draft acts", %{conn: conn, user: user, company: company} do
      act = create_act!(user, company, "issued")

      conn = post(conn, "/acts/#{act.id}/issue")

      assert redirected_to(conn) == "/acts/#{act.id}"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               Gettext.gettext(EdocApiWeb.Gettext, "This act cannot be issued.")
    end
  end

  describe "create/2" do
    test "shows upgrade prompt when trial document limit is exhausted", %{
      conn: conn,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Act Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      for _ <- 1..10 do
        assert {:ok, _quota} =
                 Monetization.consume_document_quota(
                   company.id,
                   "invoice",
                   Ecto.UUID.generate(),
                   "invoice_issued"
                 )
      end

      conn =
        post(conn, "/acts", %{
          "act" => %{
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "buyer_id" => buyer.id,
            "buyer_address" => "Buyer Address"
          },
          "items" => %{
            "0" => %{
              "name" => "Services",
              "code" => "A-1",
              "qty" => "1",
              "unit_price" => "100.00"
            }
          }
        })

      assert redirected_to(conn) == "/acts/new"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               Gettext.gettext(
                 EdocApiWeb.Gettext,
                 "Document limit reached for this billing period. Upgrade your plan to continue."
               )
    end
  end

  describe "tenant visibility" do
    test "active member sees owner-created acts on index and show pages", %{conn: conn} do
      owner = create_user!()
      Accounts.mark_email_verified!(owner.id)
      company = create_company!(owner)

      member = create_user!(%{"email" => "act-member@example.com"})
      Accounts.mark_email_verified!(member.id)

      {:ok, _invite} =
        Monetization.invite_member(company.id, %{
          "email" => member.email,
          "role" => "member"
        })

      [_membership_id] = Monetization.accept_pending_memberships_for_user(member)

      act = create_act!(owner, company, "draft")

      index_body =
        html_conn(conn, member)
        |> get("/acts")
        |> html_response(200)

      assert index_body =~ act.number

      show_body =
        html_conn(conn, member)
        |> get("/acts/#{act.id}")
        |> html_response(200)

      assert show_body =~ act.number
    end
  end

  defp create_act!(user, company, status) do
    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

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
    |> EdocApi.Repo.update!()
  end

  defp html_conn(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{user_id: user.id})
    |> put_private(:plug_skip_csrf_protection, true)
    |> put_req_header("accept", "text/html")
  end
end
