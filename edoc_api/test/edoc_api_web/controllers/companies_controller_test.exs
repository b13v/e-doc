defmodule EdocApiWeb.CompaniesControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Core.{Bank, CompanyBankAccount, KbeCode, KnpCode}
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
      company = create_company!(user)
      %{bank: bank, kbe_code: kbe_code, knp_code: knp_code} = create_payment_refs!()

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: user.id})
        |> put_private(:plug_skip_csrf_protection, true)
        |> put_req_header("accept", "text/html")

      {:ok, conn: conn, company: company, bank: bank, kbe_code: kbe_code, knp_code: knp_code}
    end

    test "shows friendly flash for invalid BIN/IIN", %{conn: conn} do
      conn =
        put(conn, "/company", %{
          "company" => company_attrs(%{"bin_iin" => "591325450022"})
        })

      assert html_response(conn, 200) =~ @bin_iin_error
    end

    test "renders add bank account toggle as a non-submit button", %{conn: conn, company: company} do
      create_company_bank_account!(company, %{"label" => "Primary"})
      create_company_bank_account!(company, %{"label" => "Secondary"})

      conn = get(conn, "/company")
      body = html_response(conn, 200)

      assert body =~
               ~S|<button type="button" onclick="toggleEdit('add-bank-form')" class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700">|
    end

    test "adds a third bank account from company settings", %{
      conn: conn,
      company: company,
      bank: bank
    } do
      create_company_bank_account!(company, %{"label" => "Primary"})
      create_company_bank_account!(company, %{"label" => "Secondary"})

      conn =
        post(conn, "/company/bank-accounts", %{
          "bank_account" => %{
            "label" => "Third account",
            "bank_id" => bank.id,
            "iban" => valid_kz_iban("1234567890123456")
          }
        })

      assert redirected_to(conn) == "/company"

      bank_accounts = EdocApi.Payments.list_company_bank_accounts_for_user(company.user_id)

      assert Enum.any?(bank_accounts, &(&1.label == "Third account"))
      assert length(bank_accounts) == 3
    end

    test "adds a third bank account when the label is left blank", %{
      conn: conn,
      company: company,
      bank: bank
    } do
      create_company_bank_account!(company, %{"label" => "Primary"})
      create_company_bank_account!(company, %{"label" => "Secondary"})

      third_iban = valid_kz_iban("1234567890123458")

      conn =
        post(conn, "/company/bank-accounts", %{
          "bank_account" => %{
            "label" => "",
            "bank_id" => bank.id,
            "iban" => third_iban
          }
        })

      assert redirected_to(conn) == "/company"

      bank_accounts = EdocApi.Payments.list_company_bank_accounts_for_user(company.user_id)
      third_account = Enum.find(bank_accounts, &(&1.iban == third_iban))

      assert third_account
      assert third_account.label != ""
      assert length(bank_accounts) == 3
    end

    test "shows bank account validation errors and keeps add form open", %{
      conn: conn,
      company: company
    } do
      create_company_bank_account!(company, %{"label" => "Primary"})
      create_company_bank_account!(company, %{"label" => "Secondary"})

      conn =
        post(conn, "/company/bank-accounts", %{
          "bank_account" => %{
            "label" => "Broken account",
            "bank_id" => "",
            "iban" => valid_kz_iban("1234567890123457")
          }
        })

      body = html_response(conn, 200)

      assert body =~ "Банк: не может быть пустым"

      assert body =~
               ~S|<form id="add-bank-form" action="/company/bank-accounts" method="post" class="mb-6 p-4 bg-gray-50 rounded-lg">|

      assert body =~ ~S|name="bank_account[iban]" value="KZ|
    end

    test "does not show legacy bank accounts with invalid IBANs", %{
      conn: conn,
      company: company,
      bank: bank,
      kbe_code: kbe_code,
      knp_code: knp_code
    } do
      Repo.insert!(%CompanyBankAccount{
        company_id: company.id,
        label: "Legacy invalid account",
        iban: "KZ0012345678901234",
        bank_id: bank.id,
        kbe_code_id: kbe_code.id,
        knp_code_id: knp_code.id,
        is_default: true
      })

      create_company_bank_account!(company, %{
        "label" => "Visible valid account",
        "bank_id" => bank.id,
        "kbe_code_id" => kbe_code.id,
        "knp_code_id" => knp_code.id,
        "iban" => valid_kz_iban("1234567890123459")
      })

      conn = get(conn, "/company")
      body = html_response(conn, 200)

      assert body =~ "Visible valid account"
      refute body =~ "Legacy invalid account"
      refute body =~ "KZ0012345678901234"
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
