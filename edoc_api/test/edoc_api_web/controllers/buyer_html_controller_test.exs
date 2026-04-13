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
    test "new page does not render top back link", %{conn: conn} do
      body =
        conn
        |> get("/buyers/new")
        |> html_response(200)

      refute body =~ "&larr;"
    end

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

    test "wraps an unquoted buyer name in double quotes", %{conn: conn, company: company} do
      conn =
        post(conn, "/buyers", %{
          "buyer" => %{
            "name" => "Buyer One",
            "bin_iin" => "060215385673"
          }
        })

      assert redirected_to(conn) == "/buyers"

      [buyer] = Buyers.list_buyers_for_company(company.id)
      assert buyer.name == ~s("Buyer One")
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

    test "replaces single quotes with double quotes in the buyer name", %{
      conn: conn,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Buyer For Update",
          "bin_iin" => "080215385677"
        })

      conn =
        put(conn, "/buyers/#{buyer.id}", %{
          "buyer" => %{
            "name" => "'Updated Buyer'",
            "bin_iin" => buyer.bin_iin
          }
        })

      assert redirected_to(conn) == "/buyers"
      assert Buyers.get_buyer(buyer.id).name == ~s("Updated Buyer")
    end
  end
end
