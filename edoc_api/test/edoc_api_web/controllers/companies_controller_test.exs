defmodule EdocApiWeb.CompaniesControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Companies
  alias EdocApi.Core.{Bank, CompanyBankAccount, KbeCode, KnpCode}
  alias EdocApi.Monetization
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

    test "wraps an unquoted company name in double quotes on setup", %{
      conn: conn,
      bank: bank,
      kbe_code: kbe_code,
      knp_code: knp_code
    } do
      user_id = get_session(conn, :user_id)

      conn =
        post(conn, "/company/setup", %{
          "company" => company_attrs(%{"name" => "Acme LLC"}),
          "bank_account" => %{
            "bank_id" => bank.id,
            "iban" => valid_kz_iban("1234567890"),
            "kbe_code_id" => kbe_code.id,
            "knp_code_id" => knp_code.id
          }
        })

      assert redirected_to(conn) == "/buyers/new"
      assert Companies.get_company_by_user_id(user_id).name == ~s("Acme LLC")
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

    test "replaces single quotes with double quotes in the company name", %{
      conn: conn,
      company: company
    } do
      conn =
        put(conn, "/company", %{
          "company" => company_attrs(%{"name" => "'Updated Company'"})
        })

      assert redirected_to(conn) == "/company"
      assert Companies.get_company_by_user_id(company.user_id).name == ~s("Updated Company")
    end

    test "renders add bank account toggle as a non-submit button", %{conn: conn, company: company} do
      create_company_bank_account!(company, %{"label" => "Primary"})
      create_company_bank_account!(company, %{"label" => "Secondary"})

      conn = get(conn, "/company")
      body = html_response(conn, 200)

      assert body =~
               ~S|<button type="button" onclick="toggleEdit('add-bank-form')" class="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700">|
    end

    test "renders company bank-account actions as a compact overflow menu", %{
      conn: conn,
      company: company
    } do
      create_company_bank_account!(company, %{"label" => "Primary"})
      account = create_company_bank_account!(company, %{"label" => "Secondary"})

      body =
        conn
        |> get("/company")
        |> html_response(200)

      assert body =~ "w-px whitespace-nowrap px-6 py-4 text-right"
      assert body =~ "min-w-44"
      refute body =~ "whitespace-nowrap md:flex"
      assert body =~ ~s(href="/company/bank-accounts/#{account.id}/edit")
      assert body =~ ~s(href="/company/bank-accounts/#{account.id}")
      assert body =~ ~s(>Действия<)
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

    test "renders live subscription usage on company settings", %{conn: conn, company: company} do
      {:ok, _sub} =
        Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "starter",
          "included_document_limit" => 50,
          "included_seat_limit" => 2,
          "add_on_seat_quantity" => 1
        })

      assert {:ok, _quota} =
               Monetization.consume_document_quota(
                 company.id,
                 "invoice",
                 Ecto.UUID.generate(),
                 "invoice_issued"
               )

      body =
        conn
        |> get("/company")
        |> html_response(200)

      assert body =~ ~s(action="/company/subscription")
      assert body =~ "Starter"
      assert body =~ "1 / 50"
      assert body =~ "1 / 2"
    end

    test "updates subscription plan and add-on seats from company settings", %{
      conn: conn,
      company: company
    } do
      conn =
        post(conn, "/company/subscription", %{
          "subscription" => %{
            "plan" => "basic",
            "add_on_seat_quantity" => "3"
          }
        })

      assert redirected_to(conn) == "/company"
      assert Monetization.effective_seat_limit(company.id) == 5

      body =
        conn
        |> recycle()
        |> get("/company")
        |> html_response(200)

      assert body =~ "Basic"
      assert body =~ "1 / 5"
      refute body =~ ~s(name="subscription[add_on_seat_quantity]")
    end

    test "blocks downgrade with localized russian warning and highlighted memberships", %{
      conn: conn,
      company: company
    } do
      {:ok, _sub} =
        Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "basic"
        })

      {:ok, _first} =
        Monetization.invite_member(company.id, %{
          "email" => "first@example.com",
          "role" => "member"
        })

      {:ok, second} =
        Monetization.invite_member(company.id, %{
          "email" => "second@example.com",
          "role" => "member"
        })

      conn =
        post(conn, "/company/subscription", %{
          "subscription" => %{
            "plan" => "starter"
          }
        })

      body = html_response(conn, 200)

      assert body =~ "Удалите 1 пользователей перед переходом на Starter."
      assert body =~
               "Перед применением этого изменения тарифа удалите выделенных участников команды."
      assert count_occurrences(body, "Удалите 1 пользователей перед переходом на Starter.") == 1

      assert count_occurrences(
               body,
               "Перед применением этого изменения тарифа удалите выделенных участников команды."
             ) == 1

      assert body =~ "second@example.com"
      assert body =~ "bg-amber-50"
      assert body =~ second.id
      assert Monetization.subscription_snapshot(company.id).plan == "basic"
    end

    test "blocks downgrade with localized kazakh warning and highlighted memberships", %{
      conn: conn,
      company: company
    } do
      {:ok, _sub} =
        Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "basic"
        })

      {:ok, _first} =
        Monetization.invite_member(company.id, %{
          "email" => "first-kk@example.com",
          "role" => "member"
        })

      {:ok, second} =
        Monetization.invite_member(company.id, %{
          "email" => "second-kk@example.com",
          "role" => "member"
        })

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          user_id: company.user_id,
          locale: "kk"
        })
        |> post("/company/subscription", %{
          "subscription" => %{
            "plan" => "starter"
          }
        })

      body = html_response(conn, 200)

      assert body =~ "Starter тарифіне ауысу үшін 1 пайдаланушыны алып тастаңыз."
      assert body =~
               "Осы тариф өзгерісін қолдану алдында белгіленген команда мүшелерін алып тастаңыз."

      assert count_occurrences(body, "Starter тарифіне ауысу үшін 1 пайдаланушыны алып тастаңыз.") ==
               1

      assert count_occurrences(
               body,
               "Осы тариф өзгерісін қолдану алдында белгіленген команда мүшелерін алып тастаңыз."
             ) == 1

      assert body =~ "second-kk@example.com"
      assert body =~ second.id
      assert Monetization.subscription_snapshot(company.id).plan == "basic"
    end

    test "renders team membership panel with invited members", %{conn: conn, company: company} do
      assert {:ok, _membership} =
               Monetization.invite_member(company.id, %{
                 "email" => "teammate@example.com",
                 "role" => "member"
               })

      body =
        conn
        |> get("/company")
        |> html_response(200)

      assert body =~ ~s(action="/company/memberships")
      assert body =~ "Команда"
      assert body =~ "teammate@example.com"
      assert body =~ "Приглашен"
    end

    test "invites a member from company settings", %{conn: conn, company: company} do
      conn =
        post(conn, "/company/memberships", %{
          "membership" => %{
            "email" => "member@example.com",
            "role" => "admin"
          }
        })

      assert redirected_to(conn) == "/company"

      assert [%{invite_email: "member@example.com", role: "admin", status: "invited"}] =
               Monetization.list_memberships(company.id)
               |> Enum.filter(&(&1.role != "owner"))
    end

    test "removes an invited member from company settings", %{conn: conn, company: company} do
      assert {:ok, membership} =
               Monetization.invite_member(company.id, %{
                 "email" => "remove-me@example.com",
                 "role" => "member"
               })

      conn = delete(conn, "/company/memberships/#{membership.id}")

      assert redirected_to(conn) == "/company"

      assert Enum.all?(Monetization.list_memberships(company.id), fn listed ->
               listed.id != membership.id
             end)
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

  defp count_occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end
end
