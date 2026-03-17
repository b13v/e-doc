defmodule EdocApiWeb.CompaniesControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Core.{Bank, KbeCode, KnpCode}
  alias EdocApi.Repo

  @bin_iin_error "Неверный БИН/ИИН. Пожалуйста, введите действительный 12-значный БИН/ИИН."

  describe "create_setup/2" do
    setup %{conn: conn} do
      user = create_user!()
      Accounts.mark_email_verified!(user.id)

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: user.id})
        |> put_private(:plug_skip_csrf_protection, true)
        |> put_req_header("accept", "text/html")

      %{bank: bank, kbe_code: kbe_code, knp_code: knp_code} = create_payment_refs!()

      {:ok, conn: conn, bank: bank, kbe_code: kbe_code, knp_code: knp_code}
    end

    test "shows friendly flash for invalid BIN/IIN", %{
      conn: conn,
      bank: bank,
      kbe_code: kbe_code,
      knp_code: knp_code
    } do
      company_params = company_attrs(%{"bin_iin" => "591325450022"})

      conn =
        post(conn, "/company/setup", %{
          "company" => company_params,
          "bank_account" => %{
            "bank_id" => bank.id,
            "iban" => valid_kz_iban("1234567890"),
            "kbe_code_id" => kbe_code.id,
            "knp_code_id" => knp_code.id
          }
        })

      assert html_response(conn, 200) =~ @bin_iin_error
    end
  end

  describe "update/2" do
    setup %{conn: conn} do
      user = create_user!()
      Accounts.mark_email_verified!(user.id)
      _company = create_company!(user)

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: user.id})
        |> put_private(:plug_skip_csrf_protection, true)
        |> put_req_header("accept", "text/html")

      {:ok, conn: conn}
    end

    test "shows friendly flash for invalid BIN/IIN", %{conn: conn} do
      conn =
        put(conn, "/company", %{
          "company" => company_attrs(%{"bin_iin" => "591325450022"})
        })

      assert html_response(conn, 200) =~ @bin_iin_error
    end
  end

  defp create_payment_refs! do
    suffix = Integer.to_string(System.unique_integer([:positive]))

    bic = "CB#{suffix |> String.pad_leading(8, "0") |> String.slice(-8, 8)}"

    bank =
      Repo.insert!(%Bank{
        name: "Company Test Bank #{suffix}",
        bic: bic
      })

    kbe_code = Repo.one(KbeCode) || Repo.insert!(%KbeCode{code: "99", description: "KBE 99"})

    knp_code =
      Repo.one(KnpCode) || Repo.insert!(%KnpCode{code: "999", description: "KNP 999"})

    %{bank: bank, kbe_code: kbe_code, knp_code: knp_code}
  end
end
