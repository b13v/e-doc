defmodule EdocApiWeb.BuyersControllerTest do
  use EdocApiWeb.ConnCase

  alias EdocApi.Core.Bank
  alias EdocApi.Repo
  import EdocApi.TestFixtures

  setup %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    {:ok, conn: authenticate(conn, user), company: company}
  end

  describe "create/2" do
    test "creates buyer with default bank data in response", %{conn: conn} do
      bank = create_bank!()

      conn =
        post(conn, "/v1/buyers", %{
          "buyer" => %{
            "name" => "API Buyer",
            "bin_iin" => "080215385677",
            "bank_id" => bank.id,
            "iban" => "KZ280000000000000010",
            "bic" => "BANKSWF1"
          }
        })

      assert response(conn, 201)
      body = json_response(conn, 201)

      assert body["name"] == "API Buyer"
      assert body["bank"]["bank_id"] == bank.id
      assert body["bank"]["bank_name"] == bank.name
      assert body["bank"]["iban"] == "KZ280000000000000010"
      assert body["bank"]["bic"] == "BANKSWF1"
    end
  end

  describe "index/2" do
    test "returns normalized pagination metadata", %{conn: conn, company: company} do
      {:ok, _buyer_1} =
        EdocApi.Buyers.create_buyer_for_company(company.id, %{
          "name" => "Buyer A",
          "bin_iin" => "060215385673"
        })

      {:ok, _buyer_2} =
        EdocApi.Buyers.create_buyer_for_company(company.id, %{
          "name" => "Buyer B",
          "bin_iin" => "070215385675"
        })

      {:ok, _buyer_3} =
        EdocApi.Buyers.create_buyer_for_company(company.id, %{
          "name" => "Buyer C",
          "bin_iin" => "080215385677"
        })

      conn = get(conn, "/v1/buyers?page=2&page_size=2")
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

  describe "update/2" do
    test "updates buyer bank info", %{conn: conn, company: company} do
      bank1 = create_bank!()
      bank2 = create_bank!()

      {:ok, buyer} =
        EdocApi.Buyers.create_buyer_for_company(company.id, %{
          "name" => "Buyer Update API",
          "bin_iin" => "070215385675",
          "bank_id" => bank1.id,
          "iban" => "KZ980000000000000011"
        })

      conn =
        put(conn, "/v1/buyers/#{buyer.id}", %{
          "buyer" => %{
            "name" => "Buyer Update API",
            "bin_iin" => "070215385675",
            "bank_id" => bank2.id,
            "iban" => "KZ710000000000000012",
            "bic" => "UPDSWFT1"
          }
        })

      assert response(conn, 200)
      body = json_response(conn, 200)

      assert body["bank"]["bank_id"] == bank2.id
      assert body["bank"]["bank_name"] == bank2.name
      assert body["bank"]["iban"] == "KZ710000000000000012"
      assert body["bank"]["bic"] == "UPDSWFT1"
    end

    test "returns 400 for malformed UUID", %{conn: conn} do
      conn = put(conn, "/v1/buyers/not-a-uuid", %{"buyer" => %{"name" => "Invalid"}})

      assert response(conn, 400)
      assert json_response(conn, 400)["error"] == "invalid_uuid"
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = EdocApi.Auth.Token.generate_access_token(user.id)
    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp create_bank! do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    bic = "BIC#{String.slice(suffix, 0, 8)}"
    Repo.insert!(%Bank{name: "API Buyer Bank #{suffix}", bic: bic})
  end
end
