defmodule EdocApiWeb.ActsControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Acts
  alias EdocApi.Buyers
  alias EdocApi.Core.Contract
  alias EdocApi.Core.ContractItem
  alias EdocApi.Documents.GeneratedDocument
  alias EdocApi.Monetization
  alias EdocApi.Repo

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

  describe "pdf/2" do
    test "returns cached pdf immediately when available", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company, "issued")

      Repo.insert!(%GeneratedDocument{
        user_id: user.id,
        document_type: "act",
        document_id: act.id,
        status: "completed",
        pdf_binary: "%PDF-cached-act"
      })

      conn = get(conn, "/acts/#{act.id}/pdf")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/pdf; charset=utf-8"]
      assert conn.resp_body == "%PDF-cached-act"
    end

    test "enqueues generation and redirects with info when cache is missing", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company, "issued")

      conn = get(conn, "/acts/#{act.id}/pdf")

      assert redirected_to(conn) == "/acts/#{act.id}"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               Gettext.gettext(
                 EdocApiWeb.Gettext,
                 "PDF is being prepared. Please try again in a few seconds."
               )
    end
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

  describe "edit/update" do
    test "draft acts can be edited from the show page", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company, "draft")

      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Updated Act Buyer",
          "bin_iin" => "060215385673",
          "address" => "Updated Buyer Address"
        })

      show_body =
        conn
        |> get("/acts/#{act.id}")
        |> html_response(200)

      assert show_body =~ ~s(href="/acts/#{act.id}/edit")

      edit_body =
        conn
        |> get("/acts/#{act.id}/edit")
        |> html_response(200)

      assert edit_body =~
               Gettext.gettext(EdocApiWeb.Gettext, "Edit Act %{number}", number: act.number)

      assert edit_body =~ ~s(action="/acts/#{act.id}")
      assert edit_body =~ "Services"

      updated_issue_date = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
      updated_actual_date = Date.utc_today() |> Date.to_iso8601()

      conn =
        put(conn, "/acts/#{act.id}", %{
          "act" => %{
            "issue_date" => updated_issue_date,
            "actual_date" => updated_actual_date,
            "buyer_id" => buyer.id,
            "buyer_address" => "Edited Buyer Address",
            "vat_rate" => "16"
          },
          "items" => %{
            "0" => %{
              "name" => "Edited services",
              "report_info" => "Report A",
              "code" => "A-2",
              "qty" => "2",
              "unit_price" => "250.00",
              "actual_date" => updated_actual_date
            }
          }
        })

      assert redirected_to(conn) == "/acts/#{act.id}"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               Gettext.gettext(EdocApiWeb.Gettext, "Act updated successfully.")

      updated = Acts.get_act_for_user(user.id, act.id)
      assert updated.issue_date == Date.from_iso8601!(updated_issue_date)
      assert updated.actual_date == Date.from_iso8601!(updated_actual_date)
      assert updated.buyer_id == buyer.id
      assert updated.buyer_name == ~s("Updated Act Buyer")
      assert updated.buyer_address == "Edited Buyer Address"
      assert [%{name: "Edited services", code: "A-2"}] = updated.items
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

    test "new act from contract shows only signed contracts that do not already have acts",
         %{
           conn: conn,
           user: user,
           company: company
         } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Act Contract Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      eligible_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "ACT-SIGNED-OK",
          "buyer_id" => buyer.id
        })

      used_draft_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "ACT-SIGNED-USED-DRAFT",
          "buyer_id" => buyer.id
        })

      used_issued_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "ACT-SIGNED-USED-ISSUED",
          "buyer_id" => buyer.id
        })

      used_signed_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "ACT-SIGNED-USED-SIGNED",
          "buyer_id" => buyer.id
        })

      _issued_only =
        create_contract!(company, %{
          "status" => "issued",
          "number" => "ACT-ISSUED-HIDE",
          "buyer_id" => buyer.id
        })

      Enum.each(
        [eligible_contract, used_draft_contract, used_issued_contract, used_signed_contract],
        fn contract ->
          %ContractItem{}
          |> ContractItem.changeset(
            %{"name" => "Services", "qty" => "1", "unit_price" => "100.00", "code" => "A-1"},
            contract.id
          )
          |> Repo.insert!()
        end
      )

      _draft_act = create_contract_act!(user, company, used_draft_contract.id, "draft")
      _issued_act = create_contract_act!(user, company, used_issued_contract.id, "issued")
      _signed_act = create_contract_act!(user, company, used_signed_contract.id, "signed")

      body =
        conn
        |> get("/acts/new")
        |> html_response(200)

      assert body =~ eligible_contract.number
      refute body =~ used_draft_contract.number
      refute body =~ used_issued_contract.number
      refute body =~ used_signed_contract.number
      refute body =~ "ACT-ISSUED-HIDE"
    end

    test "new direct act keeps buyer placeholder unselected from any concrete buyer", %{
      conn: conn,
      company: company
    } do
      {:ok, buyer_one} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Direct Buyer One",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address One"
        })

      {:ok, buyer_two} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Direct Buyer Two",
          "bin_iin" => "090215385679",
          "address" => "Buyer Address Two"
        })

      body =
        conn
        |> get("/acts/new?act_type=direct")
        |> html_response(200)

      assert body =~ ~s(id="buyer_select")
      refute body =~ ~r/<option\s+value="#{buyer_one.id}"[^>]*selected/
      refute body =~ ~r/<option\s+value="#{buyer_two.id}"[^>]*selected/
    end

    test "creates an act from a signed contract without requiring actual date", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Contract Act Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "ACT-SIGNED-CREATE",
          "buyer_id" => buyer.id
        })

      %ContractItem{}
      |> ContractItem.changeset(
        %{"name" => "Services", "qty" => "1", "unit_price" => "100.00", "code" => "A-1"},
        contract.id
      )
      |> Repo.insert!()

      conn =
        post(conn, "/acts", %{
          "act" => %{
            "act_type" => "contract",
            "contract_id" => contract.id,
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

      assert redirected_to(conn) =~ "/acts/"

      [created | _] = Acts.list_acts_for_user(user.id)
      assert created.contract_id == contract.id
      assert created.buyer_name == buyer.name
      assert created.actual_date == nil
    end

    test "rejects creating an act from a signed contract that already has a draft act", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Contract Act Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "ACT-SIGNED-USED-DRAFT-REJECT",
          "buyer_id" => buyer.id
        })

      %ContractItem{}
      |> ContractItem.changeset(
        %{"name" => "Services", "qty" => "1", "unit_price" => "100.00", "code" => "A-1"},
        contract.id
      )
      |> Repo.insert!()

      _draft_act = create_contract_act!(user, company, contract.id, "draft")

      conn =
        post(conn, "/acts", %{
          "act" => %{
            "act_type" => "contract",
            "contract_id" => contract.id,
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "actual_date" => Date.to_iso8601(Date.utc_today()),
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

      assert redirected_to(conn) == "/acts/new?act_type=contract"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               Gettext.gettext(EdocApiWeb.Gettext, "Please select a signed contract.")
    end

    test "rejects creating an act from an issued-only contract", %{
      conn: conn,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Contract Act Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      contract =
        create_contract!(company, %{
          "status" => "issued",
          "number" => "ACT-ISSUED-REJECT",
          "buyer_id" => buyer.id
        })

      conn =
        post(conn, "/acts", %{
          "act" => %{
            "act_type" => "contract",
            "contract_id" => contract.id,
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "actual_date" => Date.to_iso8601(Date.utc_today()),
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

      assert redirected_to(conn) == "/acts/new?act_type=contract"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               Gettext.gettext(EdocApiWeb.Gettext, "Please select a signed contract.")
    end
  end

  describe "index pagination" do
    test "renders paginated acts and keeps overview counts aggregated", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Paged Act Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      create_paged_act = fn status ->
        {:ok, act} =
          Acts.create_act_for_user(user.id, company.id, %{
            "issue_date" => Date.utc_today(),
            "buyer_id" => buyer.id,
            "buyer_address" => "Buyer Address",
            "items" => [
              %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
            ]
          })

        act
        |> Ecto.Changeset.change(status: status)
        |> EdocApi.Repo.update!()
      end

      draft_act = create_paged_act.("draft")
      issued_act = create_paged_act.("issued")
      signed_act = create_paged_act.("signed")

      body =
        conn
        |> get("/acts?page=1&page_size=1")
        |> html_response(200)

      numbers = [draft_act.number, issued_act.number, signed_act.number]
      assert Enum.count(numbers, &String.contains?(body, &1)) == 1

      assert body =~
               Gettext.gettext(EdocApiWeb.Gettext, "Page %{page} of %{total}", page: 1, total: 3)

      assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Draft acts")
      assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Issued acts")
      assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Signed acts")
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

    test "active member sees localized create validation flash in Russian", %{conn: conn} do
      owner = create_user!(%{"email" => "act-owner-ru@example.com"})
      Accounts.mark_email_verified!(owner.id)
      company = create_company!(owner)

      member = create_user!(%{"email" => "act-member-ru@example.com"})
      Accounts.mark_email_verified!(member.id)

      {:ok, _membership} =
        Monetization.invite_member(company.id, %{
          "email" => member.email,
          "role" => "member"
        })

      [_membership_id] = Monetization.accept_pending_memberships_for_user(member)

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: member.id, locale: "ru"})
        |> put_private(:plug_skip_csrf_protection, true)
        |> put_req_header("accept", "text/html")
        |> post("/acts", %{
          "act" => %{
            "act_type" => "direct",
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "buyer_id" => "",
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
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Выберите покупателя."
    end

    test "active admin sees localized delete flash in Kazakh", %{conn: conn} do
      owner = create_user!(%{"email" => "act-owner-kk@example.com"})
      Accounts.mark_email_verified!(owner.id)
      company = create_company!(owner)

      admin = create_user!(%{"email" => "act-admin-kk@example.com"})
      Accounts.mark_email_verified!(admin.id)

      {:ok, _membership} =
        Monetization.invite_member(company.id, %{
          "email" => admin.email,
          "role" => "admin"
        })

      [_membership_id] = Monetization.accept_pending_memberships_for_user(admin)
      draft_act = create_act!(admin, company, "draft")

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: admin.id, locale: "kk"})
        |> put_private(:plug_skip_csrf_protection, true)
        |> put_req_header("accept", "text/html")
        |> delete("/acts/#{draft_act.id}")

      assert redirected_to(conn) == "/acts"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Акт сәтті жойылды."
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

  defp create_contract_act!(user, company, contract_id, status) do
    contract = Repo.get!(Contract, contract_id)

    {:ok, act} =
      Acts.create_act_for_user(user.id, company.id, %{
        "issue_date" => Date.to_iso8601(Date.utc_today()),
        "actual_date" => Date.to_iso8601(Date.utc_today()),
        "buyer_id" => contract.buyer_id,
        "buyer_address" => "Buyer Address",
        "contract_id" => contract_id,
        "items" => [
          %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
        ]
      })

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
