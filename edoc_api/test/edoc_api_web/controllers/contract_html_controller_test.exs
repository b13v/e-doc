defmodule EdocApiWeb.ContractHTMLControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Buyers
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

    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Contract Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, conn: conn, user: user, company: company, buyer: buyer}
  end

  describe "pdf/2" do
    test "returns cached pdf immediately when available", %{
      conn: conn,
      user: user,
      company: company,
      buyer: buyer
    } do
      contract =
        create_contract!(company, %{
          "status" => "issued",
          "number" => "C-PDF-CACHED",
          "buyer_id" => buyer.id
        })

      Repo.insert!(%GeneratedDocument{
        user_id: user.id,
        document_type: "contract",
        document_id: contract.id,
        status: "completed",
        pdf_binary: "%PDF-cached-contract"
      })

      conn = get(conn, "/contracts/#{contract.id}/pdf")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/pdf; charset=utf-8"]
      assert conn.resp_body == "%PDF-cached-contract"
    end

    test "enqueues generation and redirects with info when cache is missing", %{
      conn: conn,
      company: company,
      buyer: buyer
    } do
      contract =
        create_contract!(company, %{
          "status" => "issued",
          "number" => "C-PDF-PENDING",
          "buyer_id" => buyer.id
        })

      conn = get(conn, "/contracts/#{contract.id}/pdf")

      assert redirected_to(conn) == "/contracts/#{contract.id}"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               Gettext.gettext(
                 EdocApiWeb.Gettext,
                 "PDF is being prepared. Please try again in a few seconds."
               )
    end
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

  test "index paginates contracts and keeps overview available", %{
    conn: conn,
    company: company,
    buyer: buyer
  } do
    draft_contract =
      create_contract!(company, %{
        "number" => "PAG-CON-DRAFT",
        "status" => "draft",
        "buyer_id" => buyer.id
      })

    issued_contract =
      create_contract!(company, %{
        "number" => "PAG-CON-ISSUED",
        "status" => "issued",
        "buyer_id" => buyer.id
      })

    signed_contract =
      create_contract!(company, %{
        "number" => "PAG-CON-SIGNED",
        "status" => "signed",
        "buyer_id" => buyer.id
      })

    body =
      conn
      |> get("/contracts?page=1&page_size=1")
      |> html_response(200)

    numbers = [draft_contract.number, issued_contract.number, signed_contract.number]
    assert Enum.count(numbers, &String.contains?(body, &1)) == 1

    assert body =~
             Gettext.gettext(EdocApiWeb.Gettext, "Page %{page} of %{total}", page: 1, total: 3)

    assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Draft contracts")
    assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Issued contracts")
    assert body =~ Gettext.gettext(EdocApiWeb.Gettext, "Signed contracts")
  end

  test "show renders company city and stored representative titles in contract body", %{
    conn: conn,
    user: user,
    company: _company
  } do
    issue_date = Date.utc_today()

    formatted_issue_date =
      :io_lib.format("~2..0B.~2..0B.~4..0B", [issue_date.day, issue_date.month, issue_date.year])
      |> IO.iodata_to_binary()

    company =
      create_company!(user, %{
        "city" => "Шымкент",
        "representative_name" => "Айдар Сатпаев",
        "representative_title" => "Генеральный директор"
      })

    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Buyer With Title",
        "bin_iin" => "101215385676",
        "city" => "Караганда",
        "address" => "Buyer Address",
        "director_name" => "Мария Ким",
        "director_title" => "Коммерческий директор",
        "basis" => "Доверенности"
      })

    contract =
      create_contract!(company, %{
        "number" => "CON-SHOW-CITY-TITLE",
        "buyer_id" => buyer.id,
        "city" => nil,
        "issue_date" => issue_date
      })

    body =
      conn
      |> get("/contracts/#{contract.id}")
      |> html_response(200)

    assert body =~ "<h1>ДОГОВОР № CON-SHOW-CITY-TITLE</h1>"
    assert body =~ "г. Шымкент"
    assert body =~ formatted_issue_date

    assert body =~
             ~r/в лице <strong>Коммерческий директор Мария Ким<\/strong>,\s*действующего на основании <strong>Доверенности<\/strong>/s

    assert body =~
             ~r/в лице <strong>Генеральный директор Айдар Сатпаев<\/strong>,\s*действующего на основании <strong>Устав<\/strong>/s

    refute body =~ "в лице <strong>директор Мария Ким</strong>"
    refute body =~ "в лице <strong>директор Айдар Сатпаев</strong>"
    refute body =~ "г. Астана"
  end
end
