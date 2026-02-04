defmodule EdocApiWeb.InvoiceControllerTest do
  use EdocApiWeb.ConnCase

  alias EdocApi.Invoicing
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
end
