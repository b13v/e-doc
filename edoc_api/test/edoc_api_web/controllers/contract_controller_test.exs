defmodule EdocApiWeb.ContractControllerTest do
  use EdocApiWeb.ConnCase

  alias EdocApi.Buyers
  alias EdocApi.Documents.GeneratedDocument
  alias EdocApi.Monetization
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

  describe "issue/2" do
    test "issues contract successfully", %{conn: conn, company: company} do
      contract = create_contract!(company)

      conn = post(conn, "/v1/contracts/#{contract.id}/issue")
      assert response(conn, 200)

      body = json_response(conn, 200)
      assert body["data"]["status"] == "issued"
      assert body["data"]["issued_at"]
    end

    test "returns 404 for non-existent contract", %{conn: conn} do
      fake_id = Ecto.UUID.generate()
      conn = post(conn, "/v1/contracts/#{fake_id}/issue")
      assert response(conn, 404)
      assert json_response(conn, 404)["error"] == "contract_not_found"
    end

    test "returns 422 for already issued contract", %{conn: conn, company: company} do
      contract = create_contract!(company)
      assert response(post(conn, "/v1/contracts/#{contract.id}/issue"), 200)

      conn = post(conn, "/v1/contracts/#{contract.id}/issue")
      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "contract_already_issued"
    end

    test "returns 422 when document quota is exceeded", %{conn: conn, company: company} do
      {:ok, _sub} =
        Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "starter",
          "included_document_limit" => 1,
          "included_seat_limit" => 2
        })

      contract_1 = create_contract!(company)
      contract_2 = create_contract!(company)

      assert response(post(conn, "/v1/contracts/#{contract_1.id}/issue"), 200)

      conn = post(conn, "/v1/contracts/#{contract_2.id}/issue")
      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "quota_exceeded"
    end
  end

  describe "create/2" do
    test "returns 422 when draft creation is blocked by document quota", %{
      conn: conn,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Contract API Buyer",
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
        post(conn, "/v1/contracts", %{
          "number" => "C-API-QUOTA-1",
          "issue_date" => Date.to_iso8601(Date.utc_today()),
          "buyer_id" => buyer.id,
          "status" => "draft"
        })

      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "quota_exceeded"
    end
  end

  describe "sign/2" do
    test "marks issued contract as signed", %{conn: conn, company: company} do
      contract = create_contract!(company, %{"status" => "issued"})

      conn = post(conn, "/v1/contracts/#{contract.id}/sign")
      assert response(conn, 200)

      body = json_response(conn, 200)
      assert body["data"]["status"] == "signed"
      assert body["data"]["signed_at"]
    end

    test "returns 422 for draft contract", %{conn: conn, company: company} do
      contract = create_contract!(company, %{"status" => "draft"})

      conn = post(conn, "/v1/contracts/#{contract.id}/sign")
      assert response(conn, 422)
      assert json_response(conn, 422)["error"] == "contract_not_issued"
    end
  end

  describe "index/2" do
    test "returns normalized pagination metadata", %{conn: conn, company: company} do
      _contract_1 = create_contract!(company)
      _contract_2 = create_contract!(company)
      _contract_3 = create_contract!(company)

      conn = get(conn, "/v1/contracts?page=2&page_size=2")
      assert response(conn, 200)

      body = json_response(conn, 200)
      assert length(body["data"]) == 1

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

  describe "pdf/2" do
    test "returns 202 with poll URL when pdf generation is pending", %{
      conn: conn,
      company: company
    } do
      contract = create_contract!(company)

      conn = get(conn, "/v1/contracts/#{contract.id}/pdf")

      assert conn.status == 202
      body = json_response(conn, 202)
      assert body["status"] == "pending"
      assert body["poll_url"] == "/v1/contracts/#{contract.id}/pdf/status"
    end

    test "returns cached contract pdf", %{conn: conn, user: user, company: company} do
      contract = create_contract!(company)

      Repo.insert!(%GeneratedDocument{
        user_id: user.id,
        document_type: "contract",
        document_id: contract.id,
        status: "completed",
        pdf_binary: "%PDF-api-contract"
      })

      conn = get(conn, "/v1/contracts/#{contract.id}/pdf")
      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["application/pdf; charset=utf-8"]

      assert get_resp_header(conn, "content-disposition") ==
               [~s(inline; filename="contract-#{contract.number}.pdf")]

      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
      assert get_resp_header(conn, "cache-control") == ["private, no-store, max-age=0"]
      assert conn.resp_body == "%PDF-api-contract"
    end

    test "returns ready status for cached contract pdf", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company)

      Repo.insert!(%GeneratedDocument{
        user_id: user.id,
        document_type: "contract",
        document_id: contract.id,
        status: "completed",
        pdf_binary: "%PDF-api-contract"
      })

      conn = get(conn, "/v1/contracts/#{contract.id}/pdf/status")
      assert response(conn, 200)
      assert json_response(conn, 200) == %{"status" => "ready"}
    end
  end
end
