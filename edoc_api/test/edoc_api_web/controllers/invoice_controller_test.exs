defmodule EdocApiWeb.InvoiceControllerTest do
  use EdocApiWeb.ConnCase

  import Ecto.Query, only: [from: 2]
  alias EdocApi.Billing
  alias EdocApi.Billing.Subscription
  alias EdocApi.Documents.GeneratedDocument
  alias EdocApi.Invoicing
  alias EdocApi.Repo
  import EdocApi.TestFixtures

  setup %{conn: conn} do
    user = create_user!()
    # Set verified_at to allow API access
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    {:ok, conn: authenticate(conn, user), user: user, company: company}
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = EdocApi.Auth.Token.generate_access_token(user.id)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "update/2" do
    test "updates invoice successfully", %{conn: conn, user: user, company: company} do
      invoice = create_invoice_with_items!(user, company)

      updated_attrs = %{
        "service_name" => "Updated Service",
        "buyer_name" => "Updated Buyer",
        "items" => [
          %{"name" => "Updated Item", "qty" => 1, "unit_price" => "150.00"}
        ]
      }

      conn = put(conn, "/v1/invoices/#{invoice.id}", updated_attrs)
      assert response(conn, 200)

      assert json_response(conn, 200)["invoice"]["service_name"] == "Updated Service"
      assert json_response(conn, 200)["invoice"]["buyer_name"] == "Updated Buyer"
    end

    test "returns 404 for non-existent invoice", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      conn = put(conn, "/v1/invoices/#{fake_id}", %{"service_name" => "Updated"})
      assert response(conn, 404)
    end

    test "returns 422 for already issued invoice", %{conn: conn, user: user, company: company} do
      invoice = create_invoice_with_items!(user, company)

      {:ok, issued_invoice} = Invoicing.issue_invoice_for_user(user.id, invoice.id)

      conn = put(conn, "/v1/invoices/#{issued_invoice.id}", %{"service_name" => "Updated"})
      assert response(conn, 422)

      assert json_response(conn, 422)["error"] == "invoice_already_issued"
    end

    test "rejects contract from another company", %{conn: conn, user: user, company: company} do
      other_user = create_user!()
      other_company = create_company!(other_user)
      other_contract = create_contract!(other_company)
      invoice = create_invoice_with_items!(user, company)

      updated_attrs = %{"contract_id" => other_contract.id}

      conn = put(conn, "/v1/invoices/#{invoice.id}", updated_attrs)
      assert response(conn, 422)

      assert "validation_error" in [json_response(conn, 422)["error"]]
    end
  end

  describe "create/2" do
    test "returns 422 when draft creation is blocked by document quota", %{
      conn: conn,
      company: company
    } do
      create_company_bank_account!(company)

      for _ <- 1..10 do
        assert {:ok, _quota} =
                 Billing.record_document_usage(
                   company.id,
                   "invoice",
                   Ecto.UUID.generate()
                 )
      end

      conn =
        post(conn, "/v1/invoices", %{
          "service_name" => "Quota blocked invoice",
          "issue_date" => Date.to_iso8601(Date.utc_today()),
          "currency" => "KZT",
          "buyer_name" => "Buyer LLC",
          "buyer_bin_iin" => "060215385673",
          "buyer_address" => "Buyer Address",
          "vat_rate" => "0",
          "items" => [
            %{"name" => "Service", "qty" => "1", "unit_price" => "100.00"}
          ]
        })

      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "quota_exceeded"
    end

    test "returns 422 when trial 14-day window is expired", %{conn: conn, company: company} do
      create_company_bank_account!(company)
      {:ok, _subscription} = Billing.ensure_current_subscription_for_company(company.id)
      expire_trial!(company.id, 15)

      conn =
        post(conn, "/v1/invoices", %{
          "service_name" => "Expired trial invoice",
          "issue_date" => Date.to_iso8601(Date.utc_today()),
          "currency" => "KZT",
          "buyer_name" => "Buyer LLC",
          "buyer_bin_iin" => "060215385673",
          "buyer_address" => "Buyer Address",
          "vat_rate" => "0",
          "items" => [
            %{"name" => "Service", "qty" => "1", "unit_price" => "100.00"}
          ]
        })

      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "quota_exceeded"
    end
  end

  describe "index/2" do
    test "returns normalized pagination metadata", %{conn: conn, user: user, company: company} do
      _invoice_1 = insert_invoice!(user, company, %{number: "00000000001"})
      _invoice_2 = insert_invoice!(user, company, %{number: "00000000002"})
      _invoice_3 = insert_invoice!(user, company, %{number: "00000000003"})

      conn = get(conn, "/v1/invoices?page=2&page_size=2")
      assert response(conn, 200)

      body = json_response(conn, 200)
      assert length(body["invoices"]) == 1

      assert body["meta"] == %{
               "page" => 2,
               "page_size" => 2,
               "total_count" => 3,
               "total_pages" => 2,
               "has_next" => false,
               "has_prev" => true
             }
    end
  end

  describe "pay/2" do
    test "marks issued invoice as paid", %{conn: conn, user: user, company: company} do
      invoice = create_invoice_with_items!(user, company)
      {:ok, issued_invoice} = Invoicing.issue_invoice_for_user(user.id, invoice.id)

      conn = post(conn, "/v1/invoices/#{issued_invoice.id}/pay")
      assert response(conn, 200)
      assert json_response(conn, 200)["invoice"]["status"] == "paid"
    end

    test "returns 422 for draft invoice", %{conn: conn, user: user, company: company} do
      invoice = create_invoice_with_items!(user, company)

      conn = post(conn, "/v1/invoices/#{invoice.id}/pay")
      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "cannot_mark_paid"
    end

    test "returns 422 when contract-linked invoice is paid before the contract is signed", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company, %{"status" => "issued"})

      invoice =
        insert_invoice!(user, company, %{
          status: "issued",
          contract_id: contract.id
        })

      conn = post(conn, "/v1/invoices/#{invoice.id}/pay")
      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "contract_must_be_signed_to_pay_invoice"
    end
  end

  describe "issue/2" do
    test "returns 422 when contract-linked invoice is issued before the contract is signed", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company, %{"status" => "issued"})
      invoice = create_invoice_with_items!(user, company, %{"contract_id" => contract.id})

      conn = post(conn, "/v1/invoices/#{invoice.id}/issue")
      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "contract_must_be_signed_to_issue_invoice"
    end

    test "returns 422 when document quota is exceeded", %{
      conn: conn,
      user: user,
      company: company
    } do
      activate_billing_plan!(company, "starter")

      for _ <- 1..49 do
        assert {:ok, _event} =
                 Billing.record_document_usage(company.id, "invoice", Ecto.UUID.generate())
      end

      invoice_1 = create_invoice_with_items!(user, company)
      invoice_2 = create_invoice_with_items!(user, company)

      assert response(post(conn, "/v1/invoices/#{invoice_1.id}/issue"), 200)

      conn = post(conn, "/v1/invoices/#{invoice_2.id}/issue")
      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "quota_exceeded"
    end

    test "returns 422 when trial 14-day window is expired", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_invoice_with_items!(user, company)
      {:ok, _subscription} = Billing.ensure_current_subscription_for_company(company.id)
      expire_trial!(company.id, 15)

      conn = post(conn, "/v1/invoices/#{invoice.id}/issue")
      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "quota_exceeded"
    end
  end

  describe "pdf/2" do
    test "returns 202 with poll URL when pdf generation is pending", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_invoice_with_items!(user, company)

      conn = get(conn, "/v1/invoices/#{invoice.id}/pdf")

      assert conn.status == 202
      body = json_response(conn, 202)
      assert body["status"] == "pending"
      assert body["poll_url"] == "/v1/invoices/#{invoice.id}/pdf/status"
    end

    test "returns cached invoice pdf with security headers", %{
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
        pdf_binary: "%PDF-api-invoice"
      })

      conn = get(conn, "/v1/invoices/#{invoice.id}/pdf")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["application/pdf; charset=utf-8"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
      assert get_resp_header(conn, "cache-control") == ["private, no-store, max-age=0"]
      assert conn.resp_body == "%PDF-api-invoice"
    end

    test "returns ready status for cached invoice pdf", %{
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
        pdf_binary: "%PDF-api-invoice"
      })

      conn = get(conn, "/v1/invoices/#{invoice.id}/pdf/status")
      assert response(conn, 200)
      assert json_response(conn, 200) == %{"status" => "ready"}
    end
  end

  defp expire_trial!(company_id, days_ago) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    trial_started_at = DateTime.add(now, -days_ago * 86_400, :second)
    trial_period_end = DateTime.add(trial_started_at, 14 * 86_400, :second)

    from(s in Subscription,
      where: s.company_id == ^company_id and s.status == "trialing"
    )
    |> Repo.update_all(
      set: [
        current_period_start: trial_started_at,
        current_period_end: trial_period_end,
        updated_at: now
      ]
    )
  end
end
