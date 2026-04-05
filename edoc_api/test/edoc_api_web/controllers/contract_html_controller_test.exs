defmodule EdocApiWeb.ContractHTMLControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
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

    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Contract Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, conn: conn, user: user, company: company, buyer: buyer}
  end

  test "shows upgrade prompt when trial document limit is exhausted", %{
    conn: conn,
    company: company,
    buyer: buyer
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
      post(conn, "/contracts", %{
        "contract" => %{
          "number" => "C-HTML-TRIAL-1",
          "issue_date" => Date.to_iso8601(Date.utc_today()),
          "buyer_id" => buyer.id,
          "status" => "draft"
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
