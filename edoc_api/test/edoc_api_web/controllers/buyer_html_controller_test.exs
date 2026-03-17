defmodule EdocApiWeb.BuyerHTMLControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Buyers

  @bin_iin_error "Неверный БИН/ИИН. Пожалуйста, введите действительный 12-значный БИН/ИИН."

  setup %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put_private(:plug_skip_csrf_protection, true)
      |> put_req_header("accept", "text/html")

    {:ok, conn: conn, company: company}
  end

  describe "create/2" do
    test "shows flash error for invalid BIN/IIN", %{conn: conn} do
      conn =
        post(conn, "/buyers", %{
          "buyer" => %{
            "name" => "Invalid BIN Buyer",
            "bin_iin" => "123"
          }
        })

      assert html_response(conn, 200) =~ @bin_iin_error
    end
  end

  describe "update/2" do
    test "shows flash error for BIN/IIN checksum failure", %{conn: conn, company: company} do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Buyer For Update",
          "bin_iin" => "080215385677"
        })

      conn =
        put(conn, "/buyers/#{buyer.id}", %{
          "buyer" => %{
            "name" => buyer.name,
            "bin_iin" => "591325450022"
          }
        })

      assert html_response(conn, 200) =~ @bin_iin_error
    end
  end
end
