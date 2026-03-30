defmodule EdocApiWeb.DocumentDeliveryHTMLControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import EdocApi.TestFixtures
  import Swoosh.TestAssertions

  alias EdocApi.Accounts
  alias EdocApi.Acts
  alias EdocApi.Buyers
  alias EdocApi.Core
  alias EdocApi.Invoicing

  setup %{conn: conn} do
    original_config = Application.get_env(:edoc_api, :document_delivery, [])
    original_mailer_config = Application.get_env(:edoc_api, EdocApi.Mailer, [])

    Application.put_env(
      :edoc_api,
      :document_delivery,
      Keyword.merge(original_config, renderer: EdocApi.DocumentDeliveryHTMLTestRenderer)
    )

    on_exit(fn ->
      Application.put_env(:edoc_api, :document_delivery, original_config)
      Application.put_env(:edoc_api, EdocApi.Mailer, original_mailer_config)
    end)

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

  describe "document show pages" do
    test "authenticated app header uses the Edocly brand logo", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_issued_invoice!(user, company)

      conn = get(conn, "/invoices/#{invoice.id}")

      body = html_response(conn, 200)
      assert body =~ "Edocly"
      refute body =~ "EdocAPI"
    end

    test "issued invoice show displays the Send menu", %{conn: conn, user: user, company: company} do
      invoice = create_issued_invoice!(user, company)

      conn = get(conn, "/invoices/#{invoice.id}")

      body = html_response(conn, 200)
      assert body =~ "data-send-menu-root"
      assert body =~ "Email"
      assert body =~ "WhatsApp"
      assert body =~ "Telegram"
    end

    test "draft invoice show hides the Send menu", %{conn: conn, user: user, company: company} do
      invoice = create_invoice_with_items!(user, company)

      conn = get(conn, "/invoices/#{invoice.id}")

      refute html_response(conn, 200) =~ ">Отправить<"
    end

    test "issued contract show displays the Send menu", %{conn: conn, company: company} do
      contract = create_issued_contract!(company)

      conn = get(conn, "/contracts/#{contract.id}")

      body = html_response(conn, 200)
      assert body =~ "data-send-menu-root"
      assert body =~ "Email"
      assert body =~ "WhatsApp"
      assert body =~ "Telegram"
    end

    test "act show displays the Send menu", %{conn: conn, user: user, company: company} do
      act = create_act!(user, company)

      conn = get(conn, "/acts/#{act.id}")

      body = html_response(conn, 200)
      assert body =~ "data-send-menu-root"
      assert body =~ "Email"
      assert body =~ "WhatsApp"
      assert body =~ "Telegram"
    end
  end

  describe "GET /documents/:type/:id/send/email" do
    test "returns an HTMX email panel prefilled from document data", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_issued_invoice!(user, company)

      conn =
        conn
        |> put_req_header("hx-request", "true")
        |> get("/documents/invoice/#{invoice.id}/send/email")

      body = html_response(conn, 200)
      assert body =~ "Отправить по email"
      assert body =~ "Официальный канал доставки"
      assert body =~ "recipient_email"
      assert body =~ "recipient_name"
      assert body =~ "buyer@example.com"
      assert body =~ "Buyer LLC"
    end

    test "renders the form to update the surrounding send panel", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_issued_invoice!(user, company)

      conn =
        conn
        |> put_req_header("hx-request", "true")
        |> get("/documents/invoice/#{invoice.id}/send/email")

      body = html_response(conn, 200)

      assert body =~ ~s(hx-target="closest .send-panel")
    end

    test "renders Russian localized email panels for invoices, contracts, and acts", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_issued_invoice!(user, company)
      contract = create_issued_contract!(company)
      act = create_act!(user, company)

      for {type, id} <- [{"invoice", invoice.id}, {"contract", contract.id}, {"act", act.id}] do
        body =
          conn
          |> localized_hx_conn(user, "ru")
          |> get("/documents/#{type}/#{id}/send/email")
          |> html_response(200)

        assert body =~ "Отправить по email"
        assert body =~ "Официальный канал доставки"
        assert body =~ "Имя получателя"
        assert body =~ "Email получателя"
        assert body =~ "Отправить документ"
        assert body =~ "WhatsApp и Telegram служат только дополнительными каналами отправки."

        refute body =~ "Send by Email"
        refute body =~ "Official delivery channel"
        refute body =~ "Recipient name"
        refute body =~ "Recipient email"
        refute body =~ "Send document"
      end
    end

    test "renders Kazakh localized email panels for invoices, contracts, and acts", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_issued_invoice!(user, company)
      contract = create_issued_contract!(company)
      act = create_act!(user, company)

      for {type, id} <- [{"invoice", invoice.id}, {"contract", contract.id}, {"act", act.id}] do
        body =
          conn
          |> localized_hx_conn(user, "kk")
          |> get("/documents/#{type}/#{id}/send/email")
          |> html_response(200)

        assert body =~ "Email арқылы жіберу"
        assert body =~ "Ресми жеткізу арнасы"
        assert body =~ "Алушының аты"
        assert body =~ "Алушының email-ы"
        assert body =~ "Құжатты жіберу"
        assert body =~ "WhatsApp пен Telegram тек қосымша жіберу арналары болып табылады."

        refute body =~ "Send by Email"
        refute body =~ "Official delivery channel"
        refute body =~ "Recipient name"
        refute body =~ "Recipient email"
        refute body =~ "Send document"
      end
    end
  end

  describe "POST /documents/:type/:id/send/email" do
    test "sends email from the HTMX panel and returns success markup", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_issued_invoice!(user, company)

      conn =
        conn
        |> put_req_header("hx-request", "true")
        |> post("/documents/invoice/#{invoice.id}/send/email", %{
          "recipient_name" => "Buyer LLC",
          "recipient_email" => "buyer@example.com"
        })

      body = html_response(conn, 200)
      assert body =~ "Документ отправлен"
      assert body =~ "buyer@example.com"

      assert_email_sent(fn email ->
        email.to == [{"Buyer LLC", "buyer@example.com"}] and
          email.subject =~ invoice.number
      end)
    end

    test "keeps the panel open with an error for invalid email", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_issued_invoice!(user, company)

      conn =
        conn
        |> put_req_header("hx-request", "true")
        |> post("/documents/invoice/#{invoice.id}/send/email", %{
          "recipient_name" => "Buyer LLC",
          "recipient_email" => ""
        })

      body = html_response(conn, 422)
      assert body =~ "Recipient email is required"
      assert body =~ "recipient_email"
    end

    test "shows a local mailer warning when SMTP is not configured", %{
      conn: conn,
      user: user,
      company: company
    } do
      Application.put_env(:edoc_api, EdocApi.Mailer, adapter: Swoosh.Adapters.Local)

      invoice = create_issued_invoice!(user, company)

      conn =
        conn
        |> put_req_header("hx-request", "true")
        |> post("/documents/invoice/#{invoice.id}/send/email", %{
          "recipient_name" => "Buyer LLC",
          "recipient_email" => "buyer@example.com"
        })

      body = html_response(conn, 200)
      assert body =~ "SMTP не настроен"
      assert body =~ "не было доставлено в почтовый ящик получателя"
    end

    test "renders Russian localized success responses for invoices, contracts, and acts", %{
      conn: conn,
      user: user,
      company: company
    } do
      Application.put_env(:edoc_api, EdocApi.Mailer, adapter: Swoosh.Adapters.Local)

      invoice = create_issued_invoice!(user, company)
      contract = create_issued_contract!(company)
      act = create_act!(user, company)

      for {type, id} <- [{"invoice", invoice.id}, {"contract", contract.id}, {"act", act.id}] do
        body =
          conn
          |> localized_hx_conn(user, "ru")
          |> post("/documents/#{type}/#{id}/send/email", %{
            "recipient_name" => "Buyer LLC",
            "recipient_email" => "buyer@example.com"
          })
          |> html_response(200)

        assert body =~ "Документ отправлен"
        assert body =~ "был отправлен на"
        assert body =~ "SMTP не настроен."
        assert body =~ "не было доставлено в почтовый ящик получателя"
        assert body =~ "Защищенная ссылка:"

        refute body =~ "Document sent"
        refute body =~ "was sent to"
        refute body =~ "SMTP is not configured"
        refute body =~ "Protected link:"
      end
    end

    test "renders Kazakh localized success responses for invoices, contracts, and acts", %{
      conn: conn,
      user: user,
      company: company
    } do
      Application.put_env(:edoc_api, EdocApi.Mailer, adapter: Swoosh.Adapters.Local)

      invoice = create_issued_invoice!(user, company)
      contract = create_issued_contract!(company)
      act = create_act!(user, company)

      for {type, id} <- [{"invoice", invoice.id}, {"contract", contract.id}, {"act", act.id}] do
        body =
          conn
          |> localized_hx_conn(user, "kk")
          |> post("/documents/#{type}/#{id}/send/email", %{
            "recipient_name" => "Buyer LLC",
            "recipient_email" => "buyer@example.com"
          })
          |> html_response(200)

        assert body =~ "Құжат жіберілді"
        assert body =~ "мына мекенжайға жіберілді"
        assert body =~ "SMTP бапталмаған."
        assert body =~ "алушының кіріс жәшігіне жеткізілген жоқ"
        assert body =~ "Қорғалған сілтеме:"

        refute body =~ "Document sent"
        refute body =~ "was sent to"
        refute body =~ "SMTP is not configured"
        refute body =~ "Protected link:"
      end
    end
  end

  describe "POST /documents/:type/:id/share/:channel" do
    test "redirects to the WhatsApp share URL", %{conn: conn, user: user, company: company} do
      invoice = create_issued_invoice!(user, company)

      conn = post(conn, "/documents/invoice/#{invoice.id}/share/whatsapp", %{})

      assert redirected_to(conn, 302) =~ "whatsapp://send?text="
    end

    test "redirects to the Telegram share URL", %{conn: conn, company: company} do
      contract = create_issued_contract!(company)

      conn = post(conn, "/documents/contract/#{contract.id}/share/telegram", %{})

      assert redirected_to(conn, 302) =~ "https://t.me/share/url"
    end
  end

  defp create_issued_invoice!(user, company) do
    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Buyer LLC",
        "bin_iin" => "080215385677",
        "email" => "buyer@example.com",
        "address" => "Buyer Address"
      })

    contract =
      create_contract!(company, %{
        "status" => "issued",
        "buyer_id" => buyer.id,
        "buyer_email" => buyer.email,
        "buyer_phone" => buyer.phone,
        "buyer_name" => buyer.name,
        "buyer_bin_iin" => buyer.bin_iin,
        "buyer_address" => buyer.address
      })

    invoice =
      insert_invoice!(user, company, %{
        status: "issued",
        contract_id: contract.id,
        buyer_name: buyer.name,
        buyer_bin_iin: buyer.bin_iin,
        buyer_address: buyer.address
      })

    Invoicing.get_invoice_for_user(user.id, invoice.id)
  end

  defp create_issued_contract!(company) do
    suffix = System.unique_integer([:positive])

    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Buyer LLC",
        "bin_iin" => "060215385673",
        "email" => "buyer-#{suffix}@example.com",
        "address" => "Buyer Address"
      })

    {:ok, contract} =
      Core.create_contract_for_user(
        company.user_id,
        %{
          "number" => "C-#{System.unique_integer([:positive])}",
          "issue_date" => Date.utc_today(),
          "buyer_id" => buyer.id,
          "buyer_email" => buyer.email,
          "status" => "issued"
        },
        [
          %{
            "name" => "Consulting",
            "qty" => 1,
            "unit_price" => Decimal.new("100.00"),
            "amount" => Decimal.new("100.00")
          }
        ]
      )

    contract
  end

  defp create_act!(user, company) do
    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Act Buyer",
        "bin_iin" => "101215385676",
        "email" => "act-buyer@example.com",
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
  end

  defp localized_hx_conn(conn, user, locale) do
    conn
    |> recycle()
    |> Plug.Test.init_test_session(%{user_id: user.id, locale: locale})
    |> put_private(:plug_skip_csrf_protection, true)
    |> put_req_header("accept", "text/html")
    |> put_req_header("hx-request", "true")
  end
end

defmodule EdocApi.DocumentDeliveryHTMLTestRenderer do
  def render(:invoice, invoice) do
    {:ok, pdf_binary("invoice", invoice.number)}
  end

  def render(:contract, contract) do
    {:ok, pdf_binary("contract", contract.number)}
  end

  def render(:act, act) do
    {:ok, pdf_binary("act", act.number)}
  end

  defp pdf_binary(type, number) do
    "%PDF-1.4\n#{type}:#{number}\n%%EOF"
  end
end
