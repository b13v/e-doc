defmodule EdocApiWeb.InvoicesHTMLControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Buyers
  alias EdocApi.Core.ContractItem
  alias EdocApi.Documents.GeneratedDocument
  alias EdocApi.Invoicing
  alias EdocApi.Monetization
  alias EdocApi.Repo
  alias EdocApiWeb.PdfTemplates

  @bin_iin_error "Failed to create invoice: Buyer bin iin: has invalid checksum"

  setup %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    create_company_bank_account!(company)

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
      invoice = create_invoice_with_items!(user, company)

      Repo.insert!(%GeneratedDocument{
        user_id: user.id,
        document_type: "invoice",
        document_id: invoice.id,
        status: "completed",
        pdf_binary: "%PDF-cached-invoice"
      })

      conn = get(conn, "/invoices/#{invoice.id}/pdf")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/pdf; charset=utf-8"]
      assert conn.resp_body == "%PDF-cached-invoice"
    end

    test "enqueues generation and redirects with info when cache is missing", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_invoice_with_items!(user, company)

      conn = get(conn, "/invoices/#{invoice.id}/pdf")

      assert redirected_to(conn) == "/invoices/#{invoice.id}"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               Gettext.gettext(
                 EdocApiWeb.Gettext,
                 "PDF is being prepared. Please try again in a few seconds."
               )
    end
  end

  describe "create/2" do
    test "creates a direct invoice even when legacy invoices exist without a synced counter", %{
      conn: conn,
      user: user,
      company: company
    } do
      existing_invoice = insert_invoice!(user, company)
      assert Invoicing.count_invoices_for_user(user.id) == 1

      conn =
        post(conn, "/invoices", %{
          "invoice" => %{
            "invoice_type" => "direct",
            "service_name" => "Direct invoice",
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "currency" => "KZT",
            "buyer_name" => "Second Buyer",
            "buyer_bin_iin" => "060215385673",
            "buyer_address" => "Buyer Address",
            "vat_rate" => "0"
          },
          "items" => %{
            "0" => %{
              "name" => "Service",
              "qty" => "1",
              "unit_price" => "100.00"
            }
          }
        })

      assert redirected_to(conn) =~ "/invoices/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               Gettext.gettext(EdocApiWeb.Gettext, "Invoice created successfully.")

      invoices = Invoicing.list_invoices_for_user(user.id)

      assert Invoicing.count_invoices_for_user(user.id) == 2
      assert Enum.any?(invoices, &(&1.id == existing_invoice.id and &1.number == "00000000001"))
      assert Enum.any?(invoices, &(&1.number == "00000000002"))
    end

    test "creates a direct invoice with buyer city and legal form snapshot", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Snapshot Buyer",
          "legal_form" => "Акционерное общество",
          "bin_iin" => "080215385677",
          "city" => "Астана",
          "address" => "Проспект Достык, 12"
        })

      conn =
        post(conn, "/invoices", %{
          "invoice" => %{
            "invoice_type" => "direct",
            "service_name" => "Direct invoice snapshot",
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "currency" => "KZT",
            "buyer_id" => buyer.id,
            "vat_rate" => "0"
          },
          "items" => %{
            "0" => %{
              "name" => "Service",
              "qty" => "1",
              "unit_price" => "100.00"
            }
          }
        })

      assert redirected_to(conn) =~ "/invoices/"

      [invoice | _] = Invoicing.list_invoices_for_user(user.id)

      assert Map.get(invoice, :buyer_city) == "Астана"
      assert Map.get(invoice, :buyer_legal_form) == "Акционерное общество"
    end

    test "re-renders direct invoice form with translated validation details instead of crashing",
         %{
           conn: conn
         } do
      conn =
        post(conn, "/invoices", %{
          "invoice" => %{
            "invoice_type" => "direct",
            "service_name" => "Direct invoice",
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "currency" => "KZT",
            "buyer_name" => "Broken Buyer",
            "buyer_bin_iin" => "123456789012",
            "buyer_address" => "Buyer Address",
            "vat_rate" => "0"
          },
          "items" => %{
            "0" => %{
              "name" => "Service",
              "qty" => "1",
              "unit_price" => "100.00"
            }
          }
        })

      body = html_response(conn, 200)

      assert body =~ @bin_iin_error
      refute body =~ "FunctionClauseError"
    end

    test "shows upgrade prompt when trial document limit is exhausted", %{
      conn: conn,
      company: company
    } do
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
        post(conn, "/invoices", %{
          "invoice" => %{
            "invoice_type" => "direct",
            "service_name" => "Direct invoice",
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "currency" => "KZT",
            "buyer_name" => "Quota Buyer",
            "buyer_bin_iin" => "060215385673",
            "buyer_address" => "Buyer Address",
            "vat_rate" => "0"
          },
          "items" => %{
            "0" => %{
              "name" => "Service",
              "qty" => "1",
              "unit_price" => "100.00"
            }
          }
        })

      body = html_response(conn, 200)

      assert body =~
               Gettext.gettext(
                 EdocApiWeb.Gettext,
                 "Document limit reached for this billing period. Upgrade your plan to continue."
               )
    end

    test "new invoice from contract shows only signed contracts that do not already have invoices",
         %{
           conn: conn,
           user: user,
           company: company
         } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Invoice Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      eligible_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "CON-SIGNED-OK",
          "buyer_id" => buyer.id
        })

      used_draft_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "CON-SIGNED-USED-DRAFT",
          "buyer_id" => buyer.id
        })

      used_issued_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "CON-SIGNED-USED-ISSUED",
          "buyer_id" => buyer.id
        })

      used_paid_contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "CON-SIGNED-USED-PAID",
          "buyer_id" => buyer.id
        })

      _issued_only =
        create_contract!(company, %{
          "status" => "issued",
          "number" => "CON-ISSUED-HIDE",
          "buyer_id" => buyer.id
        })

      _draft_invoice =
        create_invoice_with_items!(user, company, %{
          "contract_id" => used_draft_contract.id
        })

      issued_invoice =
        create_invoice_with_items!(user, company, %{
          "contract_id" => used_issued_contract.id
        })

      assert {:ok, _issued_invoice} = Invoicing.issue_invoice_for_user(user.id, issued_invoice.id)

      paid_invoice =
        create_invoice_with_items!(user, company, %{
          "contract_id" => used_paid_contract.id
        })

      assert {:ok, issued_paid_invoice} =
               Invoicing.issue_invoice_for_user(user.id, paid_invoice.id)

      assert {:ok, _paid_invoice} =
               Invoicing.pay_invoice_for_user(user.id, issued_paid_invoice.id)

      body =
        conn
        |> get("/invoices/new")
        |> html_response(200)

      assert body =~ eligible_contract.number
      refute body =~ used_draft_contract.number
      refute body =~ used_issued_contract.number
      refute body =~ used_paid_contract.number
      refute body =~ "CON-ISSUED-HIDE"
    end

    test "creates an invoice from a signed contract", %{conn: conn, user: user, company: company} do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Invoice Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      contract =
        create_contract!(company, %{
          "status" => "signed",
          "number" => "CON-SIGNED-CREATE",
          "buyer_id" => buyer.id
        })

      %ContractItem{}
      |> ContractItem.changeset(
        %{"name" => "Service", "qty" => "1", "unit_price" => "100.00", "code" => "C-1"},
        contract.id
      )
      |> Repo.insert!()

      conn =
        post(conn, "/invoices", %{
          "invoice" => %{
            "invoice_type" => "contract",
            "contract_id" => contract.id,
            "service_name" => "Contract invoice",
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "currency" => "KZT",
            "buyer_id" => buyer.id,
            "vat_rate" => "0"
          },
          "items" => %{
            "0" => %{
              "name" => "Service",
              "qty" => "1",
              "unit_price" => "100.00"
            }
          }
        })

      assert redirected_to(conn) =~ "/invoices/"

      [created | _] = Invoicing.list_invoices_for_user(user.id)
      assert created.contract_id == contract.id
      assert created.buyer_name == buyer.name
    end

    test "rejects creating an invoice from an issued-only contract", %{
      conn: conn,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Invoice Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      contract =
        create_contract!(company, %{
          "status" => "issued",
          "number" => "CON-ISSUED-REJECT",
          "buyer_id" => buyer.id
        })

      conn =
        post(conn, "/invoices", %{
          "invoice" => %{
            "invoice_type" => "contract",
            "contract_id" => contract.id,
            "service_name" => "Contract invoice",
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "currency" => "KZT",
            "vat_rate" => "0"
          },
          "items" => %{
            "0" => %{
              "name" => "Service",
              "qty" => "1",
              "unit_price" => "100.00"
            }
          }
        })

      body = html_response(conn, 200)

      assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Please select a signed contract.")
    end
  end

  describe "index pagination" do
    test "renders paginated invoices and keeps overview counts aggregated", %{
      conn: conn,
      user: user,
      company: company
    } do
      draft_invoice = create_invoice_with_items!(user, company, %{"number" => "00000001001"})
      issued_invoice = create_invoice_with_items!(user, company, %{"number" => "00000001002"})
      paid_invoice = create_invoice_with_items!(user, company, %{"number" => "00000001003"})

      assert {:ok, _issued} = Invoicing.issue_invoice_for_user(user.id, issued_invoice.id)
      assert {:ok, issued_paid} = Invoicing.issue_invoice_for_user(user.id, paid_invoice.id)
      assert {:ok, _paid} = Invoicing.pay_invoice_for_user(user.id, issued_paid.id)

      body =
        conn
        |> get("/invoices?page=1&page_size=1")
        |> html_response(200)

      numbers = ["00000001001", "00000001002", "00000001003"]
      assert Enum.count(numbers, &String.contains?(body, &1)) == 1

      assert body =~
               Gettext.gettext(EdocApiWeb.Gettext, "Page %{page} of %{total}", page: 1, total: 3)

      assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Draft invoices")
      assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Issued invoices")
      assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Paid invoices")
      assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Overdue invoices")
      assert body =~ ~s(href="/invoices/overdue")
      assert draft_invoice.id != issued_invoice.id
    end
  end

  describe "overdue/2" do
    test "basic tenant sees overdue issued invoices with paid action", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, _subscription} =
        Monetization.activate_subscription_for_company(company.id, %{"plan" => "basic"})

      today = Date.utc_today()

      overdue =
        insert_invoice!(user, company, %{
          number: "00000002001",
          status: "issued",
          due_date: Date.add(today, -2)
        })

      _paid =
        insert_invoice!(user, company, %{
          number: "00000002002",
          status: "paid",
          due_date: Date.add(today, -3)
        })

      _not_overdue =
        insert_invoice!(user, company, %{
          number: "00000002003",
          status: "issued",
          due_date: Date.add(today, -1)
        })

      body =
        conn
        |> get("/invoices/overdue")
        |> html_response(200)

      assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Overdue invoices")
      assert body =~ overdue.number
      refute body =~ "00000002002"
      refute body =~ "00000002003"
      assert body =~ ~s(action="/invoices/#{overdue.id}/pay")
      assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Due date")
    end

    test "starter tenant sees upgrade prompt instead of overdue invoices", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, _subscription} =
        Monetization.activate_subscription_for_company(company.id, %{"plan" => "starter"})

      invoice =
        insert_invoice!(user, company, %{
          number: "00000002004",
          status: "issued",
          due_date: Date.add(Date.utc_today(), -2)
        })

      body =
        conn
        |> get("/invoices/overdue")
        |> html_response(200)

      assert body =~
               Gettext.gettext(EdocApiWeb.Gettext, "Overdue invoices are available on Basic.")

      assert body =~
               ~s(class="overdue-upgrade-card rounded-3xl border border-amber-200 bg-amber-50 px-6 py-10 shadow-sm dark:border-slate-600 dark:bg-slate-950")

      assert body =~ "overdue-upgrade-card"
      assert body =~ "overdue-upgrade-text"
      assert body =~ "html[data-theme=\"dark\"] .overdue-upgrade-text"
      assert body =~ "color: #ffffff !important;"
      refute body =~ invoice.number
    end

    test "paid overdue invoice no longer appears in overdue query", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, _subscription} =
        Monetization.activate_subscription_for_company(company.id, %{"plan" => "basic"})

      invoice =
        insert_invoice!(user, company, %{
          number: "00000002005",
          status: "issued",
          due_date: Date.add(Date.utc_today(), -2)
        })

      assert Invoicing.count_overdue_invoices_for_user(user.id) == 1

      pay_conn = post(conn, "/invoices/#{invoice.id}/pay", %{})
      assert redirected_to(pay_conn) == "/invoices/#{invoice.id}"
      assert Invoicing.count_overdue_invoices_for_user(user.id) == 0

      body =
        html_conn(conn, user)
        |> get("/invoices/overdue")
        |> html_response(200)

      refute body =~ invoice.number
    end
  end

  describe "tenant visibility" do
    test "active member sees owner-created invoices on index and show pages", %{conn: conn} do
      owner = create_user!()
      Accounts.mark_email_verified!(owner.id)
      company = create_company!(owner)
      create_company_bank_account!(company)

      member = create_user!(%{"email" => "invoice-member@example.com"})
      Accounts.mark_email_verified!(member.id)

      {:ok, _invite} =
        Monetization.invite_member(company.id, %{
          "email" => member.email,
          "role" => "member"
        })

      [_membership_id] = Monetization.accept_pending_memberships_for_user(member)

      invoice = create_invoice_with_items!(owner, company)

      member_conn = html_conn(conn, member)

      index_body =
        member_conn
        |> get("/invoices")
        |> html_response(200)

      assert index_body =~ invoice.number

      show_body =
        html_conn(conn, member)
        |> get("/invoices/#{invoice.id}")
        |> html_response(200)

      assert show_body =~ invoice.number
    end
  end

  describe "buyer party rendering" do
    test "renders complete buyer party line on the invoice show page for direct invoices", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Preview Buyer",
          "legal_form" => "Акционерное общество",
          "bin_iin" => "080215385677",
          "city" => "Астана",
          "address" => "Проспект Мәңгілік Ел, 10"
        })

      create_conn =
        post(conn, "/invoices", %{
          "invoice" => %{
            "invoice_type" => "direct",
            "service_name" => "Preview invoice",
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "currency" => "KZT",
            "buyer_id" => buyer.id,
            "vat_rate" => "0"
          },
          "items" => %{
            "0" => %{
              "name" => "Service",
              "qty" => "1",
              "unit_price" => "100.00"
            }
          }
        })

      assert redirected_to(create_conn) =~ "/invoices/"
      [invoice | _] = Invoicing.list_invoices_for_user(user.id)

      body =
        html_conn(conn, user)
        |> get("/invoices/#{invoice.id}")
        |> html_response(200)

      assert body =~
               "БИН/ИИН #{invoice.buyer_bin_iin}, Акционерное общество &quot;Preview Buyer&quot;, Республика Казахстан, г. Астана, #{invoice.buyer_address}"
    end

    test "renders the same complete buyer party line in invoice PDF html", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "PDF Buyer",
          "legal_form" => "Акционерное общество",
          "bin_iin" => "080215385677",
          "city" => "Астана",
          "address" => "Улица Сыганак, 14"
        })

      create_conn =
        post(conn, "/invoices", %{
          "invoice" => %{
            "invoice_type" => "direct",
            "service_name" => "PDF invoice",
            "issue_date" => Date.to_iso8601(Date.utc_today()),
            "currency" => "KZT",
            "buyer_id" => buyer.id,
            "vat_rate" => "0"
          },
          "items" => %{
            "0" => %{
              "name" => "Service",
              "qty" => "1",
              "unit_price" => "100.00"
            }
          }
        })

      assert redirected_to(create_conn) =~ "/invoices/"
      [invoice | _] = Invoicing.list_invoices_for_user(user.id)

      invoice = Invoicing.get_invoice_for_user(user.id, invoice.id)
      html = PdfTemplates.invoice_html(invoice)

      assert html =~
               "БИН/ИИН #{invoice.buyer_bin_iin}, Акционерное общество &quot;PDF Buyer&quot;, Республика Казахстан, г. Астана, #{invoice.buyer_address}"
    end

    test "keeps punctuation clean when buyer city and legal form are missing", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice =
        create_invoice_with_items!(user, company, %{
          "buyer_name" => "Minimal Buyer",
          "buyer_bin_iin" => "060215385673",
          "buyer_address" => "Buyer Address"
        })

      body =
        html_conn(conn, user)
        |> get("/invoices/#{invoice.id}")
        |> html_response(200)

      assert body =~
               "БИН/ИИН #{invoice.buyer_bin_iin}, #{invoice.buyer_name}, Республика Казахстан, #{invoice.buyer_address}"

      refute body =~ ", ,"
    end
  end

  defp html_conn(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{user_id: user.id})
    |> put_private(:plug_skip_csrf_protection, true)
    |> put_req_header("accept", "text/html")
  end
end
