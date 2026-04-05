defmodule EdocApiWeb.InvoicesHTMLControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Invoicing
  alias EdocApi.Monetization

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

    test "re-renders direct invoice form with translated validation details instead of crashing", %{
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
  end
end
