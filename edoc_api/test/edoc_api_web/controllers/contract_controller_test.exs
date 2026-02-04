defmodule EdocApiWeb.ContractControllerTest do
  use EdocApiWeb.ConnCase

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
  end

  describe "pdf/2" do
    if System.find_executable("wkhtmltopdf") do
      test "returns contract pdf", %{conn: conn, company: company} do
        contract = create_contract!(company)

        conn = get(conn, "/v1/contracts/#{contract.id}/pdf")
        assert response(conn, 200)
        assert get_resp_header(conn, "content-type") == ["application/pdf; charset=utf-8"]

        assert get_resp_header(conn, "content-disposition") ==
                 [~s(inline; filename="contract-#{contract.number}.pdf")]
      end
    else
      @tag skip: "wkhtmltopdf is not available in PATH"
      test "returns contract pdf", %{conn: conn, company: company} do
        contract = create_contract!(company)
        conn = get(conn, "/v1/contracts/#{contract.id}/pdf")
        assert response(conn, 200)
      end
    end
  end
end
