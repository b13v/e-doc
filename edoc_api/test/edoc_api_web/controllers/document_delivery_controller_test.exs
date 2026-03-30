defmodule EdocApiWeb.DocumentDeliveryControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import EdocApi.TestFixtures
  import Swoosh.TestAssertions

  alias EdocApi.Acts
  alias EdocApi.Buyers
  alias EdocApi.DocumentDelivery.Delivery
  alias EdocApi.Repo

  setup %{conn: conn} do
    original_config = Application.get_env(:edoc_api, :document_delivery, [])
    original_mailer_config = Application.get_env(:edoc_api, EdocApi.Mailer, [])

    Application.put_env(
      :edoc_api,
      :document_delivery,
      Keyword.merge(original_config, renderer: EdocApi.DocumentDeliveryTestRenderer)
    )

    on_exit(fn ->
      Application.put_env(:edoc_api, :document_delivery, original_config)
      Application.put_env(:edoc_api, EdocApi.Mailer, original_mailer_config)
    end)

    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, conn: authenticate(conn, user), user: user, company: company}
  end

  describe "POST /v1/documents/:type/:id/send-email" do
    test "sends invoice email with attachment and public link", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_invoice_with_items!(user, company)

      conn =
        post(conn, "/v1/documents/invoice/#{invoice.id}/send-email", %{
          "recipient_email" => "buyer@example.com",
          "recipient_name" => "Buyer LLC"
        })

      assert response(conn, 200)

      body = json_response(conn, 200)
      assert body["delivery"]["channel"] == "email"
      assert body["delivery"]["kind"] == "official"
      assert body["delivery"]["status"] == "sent"
      assert body["delivery"]["recipient_email"] == "buyer@example.com"
      assert is_binary(body["public_link"])
      assert body["document"]["type"] == "invoice"
      assert body["document"]["title"] =~ invoice.number

      public_link = body["public_link"]

      assert_email_sent(fn email ->
        email.to == [{"Buyer LLC", "buyer@example.com"}] and
          email.subject =~ invoice.number and
          email.text_body =~ public_link and
          Enum.any?(email.attachments, &(&1.filename == "invoice-#{invoice.number}.pdf"))
      end)
    end

    test "returns local preview transport info when SMTP is not configured", %{
      conn: conn,
      user: user,
      company: company
    } do
      Application.put_env(:edoc_api, EdocApi.Mailer, adapter: Swoosh.Adapters.Local)

      invoice = create_invoice_with_items!(user, company)

      conn =
        post(conn, "/v1/documents/invoice/#{invoice.id}/send-email", %{
          "recipient_email" => "buyer@example.com",
          "recipient_name" => "Buyer LLC"
        })

      body = json_response(conn, 200)
      assert body["transport"]["mode"] == "local_preview"
      assert body["transport"]["warning"] =~ "SMTP is not configured"
      assert body["transport"]["warning"] =~ "not delivered to the recipient inbox"
    end
  end

  describe "POST /v1/documents/:type/:id/share/:channel" do
    test "returns a WhatsApp payload for invoices", %{conn: conn, user: user, company: company} do
      invoice = create_invoice_with_items!(user, company)

      conn =
        post(conn, "/v1/documents/invoice/#{invoice.id}/share/whatsapp", %{
          "locale" => "ru",
          "recipient_name" => "Buyer LLC"
        })

      assert response(conn, 200)

      body = json_response(conn, 200)
      assert body["delivery"]["channel"] == "whatsapp"
      assert body["delivery"]["kind"] == "share"
      assert body["delivery"]["status"] == "sent"
      assert body["share"]["channel"] == "whatsapp"
      assert body["share"]["title"] =~ invoice.number
      assert body["share"]["share_text"] =~ invoice.number
      assert body["share"]["share_url"] =~ "whatsapp://send?text="
      assert body["share"]["public_link"] == body["public_link"]
    end

    test "supports acts through the generic share endpoint", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company)

      conn =
        post(conn, "/v1/documents/act/#{act.id}/share/telegram", %{
          "locale" => "kk"
        })

      assert response(conn, 200)

      body = json_response(conn, 200)
      assert body["delivery"]["channel"] == "telegram"
      assert body["delivery"]["status"] == "sent"
      assert body["share"]["channel"] == "telegram"
      assert body["share"]["share_text"] =~ act.number
      assert body["share"]["share_url"] =~ "https://t.me/share/url"
    end
  end

  describe "public token routes" do
    test "renders preview and marks linked delivery opened", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_invoice_with_items!(user, company)

      delivery_response =
        conn
        |> post("/v1/documents/invoice/#{invoice.id}/share/telegram", %{"locale" => "ru"})
        |> json_response(200)

      token = extract_token!(delivery_response["public_link"])
      delivery_id = delivery_response["delivery"]["id"]

      public_conn = build_conn() |> get("/public/docs/#{token}")

      assert html_response(public_conn, 200) =~ invoice.number

      delivery = Repo.get!(Delivery, delivery_id)
      assert delivery.opened_at
    end

    test "streams PDF for a valid token", %{conn: conn, company: company} do
      contract = create_contract!(company)

      delivery_response =
        conn
        |> post("/v1/documents/contract/#{contract.id}/share/telegram", %{"locale" => "ru"})
        |> json_response(200)

      token = extract_token!(delivery_response["public_link"])
      public_conn = build_conn() |> get("/public/docs/#{token}/pdf")

      assert response(public_conn, 200)
      assert get_resp_header(public_conn, "content-type") == ["application/pdf; charset=utf-8"]
      assert get_resp_header(public_conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(public_conn, "pragma") == ["no-cache"]
      assert get_resp_header(public_conn, "cache-control") == ["private, no-store, max-age=0"]
    end

    test "returns 404 for an invalid token", %{conn: _conn} do
      public_conn = build_conn() |> get("/public/docs/not-a-real-token")
      assert response(public_conn, 404)
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = EdocApi.Auth.Token.generate_access_token(user.id)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp create_act!(user, company) do
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
  end

  defp extract_token!(public_link) do
    public_link
    |> URI.parse()
    |> Map.fetch!(:path)
    |> String.split("/", trim: true)
    |> List.last()
  end
end

defmodule EdocApi.DocumentDeliveryTestRenderer do
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
