defmodule EdocApiWeb.CompaniesControllerTest do
  use EdocApiWeb.ConnCase

  import Ecto.Query, warn: false
  import EdocApi.TestFixtures
  import Swoosh.TestAssertions

  alias EdocApi.Accounts
  alias EdocApi.Billing
  alias EdocApi.Companies
  alias EdocApi.Core.{Bank, CompanyBankAccount, KbeCode, KnpCode}
  alias EdocApi.Core.TenantMembership
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

    test "does not render KNP code on the company setup form", %{conn: conn} do
      conn = get(conn, "/company/setup")
      body = html_response(conn, 200)

      refute body =~ ~s(name="bank_account[knp_code_id]")
      refute body =~ ~s(id="bank_account_knp_code_id")
      refute body =~ "KNP code"
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

    test "names missing company setup fields in the flash message", %{
      conn: conn,
      bank: bank,
      kbe_code: kbe_code,
      knp_code: knp_code
    } do
      company_params = Map.delete(company_attrs(), "name")

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

      body = html_response(conn, 200)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Заполните обязательные поля: Название компании"

      assert body =~ "Заполните обязательные поля: Название компании"
      refute body =~ "Исправьте ошибки ниже."
    end

    test "names missing initial bank account fields in the flash message", %{
      conn: conn,
      bank: _bank,
      kbe_code: kbe_code,
      knp_code: _knp_code
    } do
      user_id = get_session(conn, :user_id)

      conn =
        post(conn, "/company/setup", %{
          "company" => company_attrs(),
          "bank_account" => %{
            "bank_id" => "",
            "iban" => valid_kz_iban("1234567890"),
            "kbe_code_id" => kbe_code.id
          }
        })

      body = html_response(conn, 200)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Заполните обязательные поля: Банк"

      assert body =~ "Заполните обязательные поля: Банк"
      refute body =~ "Failed to create the bank account. Please try again."
      refute Companies.get_company_by_user_id(user_id)
    end

    test "wraps an unquoted company name in double quotes on setup", %{
      conn: conn,
      bank: bank,
      kbe_code: kbe_code,
      knp_code: _knp_code
    } do
      user_id = get_session(conn, :user_id)

      conn =
        post(conn, "/company/setup", %{
          "company" => company_attrs(%{"name" => "Acme LLC"}),
          "bank_account" => %{
            "bank_id" => bank.id,
            "iban" => valid_kz_iban("1234567890"),
            "kbe_code_id" => kbe_code.id
          }
        })

      assert redirected_to(conn) == "/buyers/new"
      assert Companies.get_company_by_user_id(user_id).name == ~s("Acme LLC")
    end

    test "creates company setup when phone is omitted because the setup form marks it optional",
         %{
           conn: conn,
           bank: bank,
           kbe_code: kbe_code
         } do
      company_params = Map.delete(company_attrs(), "phone")

      conn =
        post(conn, "/company/setup", %{
          "company" => company_params,
          "bank_account" => %{
            "bank_id" => bank.id,
            "iban" => valid_kz_iban("1234567890"),
            "kbe_code_id" => kbe_code.id
          }
        })

      assert redirected_to(conn) == "/buyers/new"
    end

    test "creates company setup without KNP because KNP is invoice-specific", %{
      conn: conn,
      bank: bank,
      kbe_code: kbe_code
    } do
      user_id = get_session(conn, :user_id)

      conn =
        post(conn, "/company/setup", %{
          "company" => company_attrs(),
          "bank_account" => %{
            "bank_id" => bank.id,
            "iban" => valid_kz_iban("1234567890"),
            "kbe_code_id" => kbe_code.id
          }
        })

      assert redirected_to(conn) == "/buyers/new"
      assert Companies.get_company_by_user_id(user_id)
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

    test "links to the tenant billing page", %{conn: conn} do
      body =
        conn
        |> get("/company")
        |> html_response(200)

      assert body =~ ~s(href="/company/billing")
    end

    test "shows outstanding billing invoice banner on company page", %{
      conn: conn,
      company: company
    } do
      {:ok, _plans} = Billing.seed_default_plans()
      {:ok, subscription} = Billing.create_trial_subscription(company)
      {:ok, subscription} = Billing.activate_subscription(subscription, "basic")
      {:ok, invoice} = Billing.create_renewal_invoice(subscription, "basic")
      {:ok, _invoice} = Billing.send_billing_invoice(invoice)

      body =
        conn
        |> get("/company")
        |> html_response(200)

      assert body =~ "company-billing-alert"
      assert body =~ "1"
      assert body =~ ~s(href="/company/billing")
      assert body =~ "неоплаченный"
    end

    test "renders context-specific company billing labels in russian", %{
      conn: conn,
      company: company
    } do
      {:ok, _plans} = Billing.seed_default_plans()
      {:ok, subscription} = Billing.create_trial_subscription(company)
      {:ok, subscription} = Billing.activate_subscription(subscription, "basic")
      {:ok, invoice} = Billing.create_renewal_invoice(subscription, "basic")
      {:ok, _invoice} = Billing.send_billing_invoice(invoice)

      body =
        conn
        |> Plug.Test.init_test_session(%{user_id: company.user_id, locale: "ru"})
        |> get("/company")
        |> html_response(200)

      assert body =~ "Оплатить"
      assert body =~ "Детали подписки"
      refute body =~ ">Billing<"
      refute body =~ ">Оплата<"
      assert count_occurrences(body, ~s(href="/company/billing")) >= 2
    end

    test "renders context-specific company billing labels in kazakh", %{
      conn: conn,
      company: company
    } do
      {:ok, _plans} = Billing.seed_default_plans()
      {:ok, subscription} = Billing.create_trial_subscription(company)
      {:ok, subscription} = Billing.activate_subscription(subscription, "basic")
      {:ok, invoice} = Billing.create_renewal_invoice(subscription, "basic")
      {:ok, _invoice} = Billing.send_billing_invoice(invoice)

      body =
        conn
        |> Plug.Test.init_test_session(%{user_id: company.user_id, locale: "kk"})
        |> get("/company")
        |> html_response(200)

      assert body =~ "Төлеу"
      assert body =~ "Жазылым мәліметтері"
      refute body =~ ">Billing<"
    end

    test "does not show outstanding billing invoice banner when nothing is due", %{conn: conn} do
      body =
        conn
        |> get("/company")
        |> html_response(200)

      refute body =~ "company-billing-alert"
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
               ~r/<form id="add-bank-form" action="\/company\/bank-accounts" method="post" class="mb-6 rounded-lg bg-gray-50 p-4 dark:bg-slate-800">/

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

    test "shows pending seat reason after invited user accepts invite while seats are full", %{
      conn: conn,
      company: company
    } do
      first_user = create_user!(%{"email" => "seat-first-ui@example.com"})
      second_user = create_user!(%{"email" => "seat-second-ui@example.com"})

      {:ok, _sub} =
        Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "basic"
        })

      assert {:ok, first_membership} =
               Monetization.invite_member(company.id, %{
                 "email" => first_user.email,
                 "role" => "member"
               })

      assert {:ok, _second_membership} =
               Monetization.invite_member(company.id, %{
                 "email" => second_user.email,
                 "role" => "member"
               })

      first_membership_id = first_membership.id

      assert [^first_membership_id] = Monetization.accept_pending_memberships_for_user(first_user)

      {:ok, _starter_sub} =
        Monetization.activate_subscription_for_company(company.id, %{
          "plan" => "starter"
        })

      assert [] = Monetization.accept_pending_memberships_for_user(second_user)

      body =
        conn
        |> get("/company")
        |> html_response(200)

      assert body =~ second_user.email
      assert body =~ "Ожидает место"
      assert body =~ "Приглашение принято, но свободных мест сейчас нет."
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

    test "invites a member and sends russian invitation email with Edocly branding", %{
      conn: conn
    } do
      invitee_email = "member-invite@example.com"

      conn =
        post(conn, "/company/memberships", %{
          "membership" => %{
            "email" => invitee_email,
            "role" => "member"
          }
        })

      assert redirected_to(conn) == "/company"

      signup_link = "http://localhost:4000/signup?email=#{URI.encode_www_form(invitee_email)}"

      assert_email_sent(fn email ->
        Enum.any?(email.to, fn {_name, address} -> address == invitee_email end) and
          email.subject =~ "Приглашение" and
          email.subject =~ "Edocly" and
          email.text_body =~ "Вас пригласили в компанию" and
          email.text_body =~ "перейдите по ссылке для регистрации" and
          email.text_body =~ "Если у вас уже есть аккаунт" and
          email.text_body =~ "Пригласил:" and
          email.text_body =~ signup_link and
          email.text_body =~ "Edocly" and
          not String.contains?(email.text_body, "EdocAPI") and
          not String.contains?(email.text_body, "You have been invited")
      end)
    end

    test "invites a member and sends kazakh invitation email when locale is kk", %{
      conn: conn
    } do
      invitee_email = "member-invite-kk@example.com"

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          user_id: get_session(conn, :user_id),
          locale: "kk"
        })
        |> post("/company/memberships", %{
          "membership" => %{
            "email" => invitee_email,
            "role" => "member"
          }
        })

      assert redirected_to(conn) == "/company"

      signup_link = "http://localhost:4000/signup?email=#{URI.encode_www_form(invitee_email)}"

      assert_email_sent(fn email ->
        Enum.any?(email.to, fn {_name, address} -> address == invitee_email end) and
          email.subject =~ "Шақыру" and
          email.subject =~ "Edocly" and
          email.text_body =~ "Сізді Edocly жүйесіндегі компанияға шақырды" and
          email.text_body =~ "Тіркелу үшін келесі сілтемеге өтіңіз" and
          email.text_body =~ "Егер осы email-пен аккаунтыңыз бар болса" and
          email.text_body =~ "Шақырған:" and
          email.text_body =~ signup_link and
          email.text_body =~ "Edocly" and
          not String.contains?(email.text_body, "EdocAPI") and
          not String.contains?(email.text_body, "You have been invited")
      end)
    end

    test "shows seat limit error when inviting more members than allowed", %{
      conn: conn,
      company: company
    } do
      conn =
        post(conn, "/company/memberships", %{
          "membership" => %{
            "email" => "first-seat@example.com",
            "role" => "member"
          }
        })

      assert redirected_to(conn) == "/company"

      conn =
        conn
        |> recycle()
        |> post("/company/memberships", %{
          "membership" => %{
            "email" => "second-seat@example.com",
            "role" => "member"
          }
        })

      assert redirected_to(conn) == "/company"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               Gettext.gettext(
                 EdocApiWeb.Gettext,
                 "No seats available. Upgrade your subscription to invite more users."
               )

      assert [
               %{invite_email: "first-seat@example.com", status: "invited"}
             ] =
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

    test "shows conflict flash when invoice numbers collide during member reassignment", %{
      conn: conn,
      company: company
    } do
      owner_id = get_session(conn, :user_id)
      member = create_user!(%{"email" => "invoice-conflict-member@example.com"})

      membership =
        %TenantMembership{}
        |> TenantMembership.changeset(%{
          company_id: company.id,
          user_id: member.id,
          role: "member",
          status: "active"
        })
        |> Repo.insert!()

      _owner_invoice =
        insert_invoice!(Accounts.get_user(owner_id), company, %{number: "99999000001"})

      _member_invoice = insert_invoice!(member, company, %{number: "99999000001"})

      conn = delete(conn, "/company/memberships/#{membership.id}")

      assert redirected_to(conn) == "/company"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Невозможно удалить участника: при переназначении возник конфликт номеров счетов."

      assert Repo.get(TenantMembership, membership.id)
    end

    test "shows owner-missing flash when no owner exists for reassignment", %{
      conn: conn,
      company: company
    } do
      owner_id = get_session(conn, :user_id)
      admin_user = create_user!(%{"email" => "member-remove-admin@example.com"})
      member_user = create_user!(%{"email" => "member-remove-user@example.com"})
      Accounts.mark_email_verified!(admin_user.id)
      Accounts.mark_email_verified!(member_user.id)

      %TenantMembership{}
      |> TenantMembership.changeset(%{
        company_id: company.id,
        user_id: admin_user.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      member_membership =
        %TenantMembership{}
        |> TenantMembership.changeset(%{
          company_id: company.id,
          user_id: member_user.id,
          role: "member",
          status: "active"
        })
        |> Repo.insert!()

      owner_membership =
        TenantMembership
        |> where(
          [m],
          m.company_id == ^company.id and m.user_id == ^owner_id and m.role == "owner" and
            m.status == "active"
        )
        |> Repo.one!()

      Repo.delete!(owner_membership)

      admin_conn = html_conn(conn, admin_user)
      conn = delete(admin_conn, "/company/memberships/#{member_membership.id}")

      assert redirected_to(conn) == "/company"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Владелец компании не найден. Восстановите владельца и повторите попытку."

      assert Repo.get(TenantMembership, member_membership.id)
      assert Repo.get(Accounts.User, member_user.id)
    end
  end

  describe "role guards" do
    setup %{conn: conn} do
      owner = create_user!()
      Accounts.mark_email_verified!(owner.id)
      company = create_company!(owner)

      {:ok, _sub} =
        Monetization.activate_subscription_for_company(company.id, %{"plan" => "basic"})

      member_user = create_user!(%{"email" => "member-role@example.com"})
      admin_user = create_user!(%{"email" => "admin-role@example.com"})

      Accounts.mark_email_verified!(member_user.id)
      Accounts.mark_email_verified!(admin_user.id)

      {:ok, _member_invite} =
        Monetization.invite_member(company.id, %{
          "email" => member_user.email,
          "role" => "member"
        })

      {:ok, _admin_invite} =
        Monetization.invite_member(company.id, %{
          "email" => admin_user.email,
          "role" => "member"
        })

      [member_membership_id] = Monetization.accept_pending_memberships_for_user(member_user)
      [admin_membership_id] = Monetization.accept_pending_memberships_for_user(admin_user)

      member_membership = Repo.get!(TenantMembership, member_membership_id)
      admin_membership = Repo.get!(TenantMembership, admin_membership_id)

      {:ok, _updated_admin} =
        admin_membership
        |> Ecto.Changeset.change(role: "admin")
        |> Repo.update()

      {:ok,
       conn: conn,
       company: company,
       member_conn: html_conn(conn, member_user),
       admin_conn: html_conn(conn, admin_user),
       member_membership_id: member_membership.id}
    end

    test "member cannot update subscription via /company/subscription", %{
      member_conn: conn,
      company: company
    } do
      before_plan = Monetization.subscription_snapshot(company.id).plan

      conn =
        post(conn, "/company/subscription", %{
          "subscription" => %{"plan" => "basic"}
        })

      assert redirected_to(conn) == "/company"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Только владелец или администратор может управлять тарифом и участниками команды."

      assert Monetization.subscription_snapshot(company.id).plan == before_plan
    end

    test "member cannot invite via /company/memberships", %{member_conn: conn, company: company} do
      before_count = Enum.count(Monetization.list_memberships(company.id))

      conn =
        post(conn, "/company/memberships", %{
          "membership" => %{
            "email" => "blocked-member@example.com",
            "role" => "member"
          }
        })

      assert redirected_to(conn) == "/company"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Только владелец или администратор может управлять тарифом и участниками команды."

      assert Enum.count(Monetization.list_memberships(company.id)) == before_count
    end

    test "member cannot remove via /company/memberships/:id", %{
      member_conn: conn,
      company: company,
      member_membership_id: membership_id
    } do
      before_count = Enum.count(Monetization.list_memberships(company.id))

      conn = delete(conn, "/company/memberships/#{membership_id}")

      assert redirected_to(conn) == "/company"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Только владелец или администратор может управлять тарифом и участниками команды."

      assert Enum.count(Monetization.list_memberships(company.id)) == before_count
    end

    test "member company page does not render actionable billing or team controls", %{
      member_conn: conn
    } do
      body =
        conn
        |> get("/company")
        |> html_response(200)

      refute body =~ ~s(name="subscription[plan]")
      refute body =~ ~s(name="membership[email]")
      refute body =~ ~s(name="membership[role]")
      refute body =~ ~S|<button type="submit" class="text-red-600 hover:text-red-800">|

      assert length(
               Regex.scan(
                 ~r/class="[^"]*rounded-2xl[^"]*dark:text-slate-100[^"]*"[^>]*>\s*Только владелец или администратор может управлять тарифом и участниками команды\./u,
                 body
               )
             ) >= 2
    end

    test "admin can still update subscription, invite, and remove members", %{
      admin_conn: conn,
      company: company
    } do
      conn =
        post(conn, "/company/subscription", %{
          "subscription" => %{"plan" => "basic"}
        })

      assert redirected_to(conn) == "/company"
      assert Monetization.subscription_snapshot(company.id).plan == "basic"

      invitee_email = "admin-invite-#{System.unique_integer([:positive])}@example.com"

      conn =
        conn
        |> recycle()
        |> post("/company/memberships", %{
          "membership" => %{
            "email" => invitee_email,
            "role" => "member"
          }
        })

      assert redirected_to(conn) == "/company"

      invited_membership =
        Monetization.list_memberships(company.id)
        |> Enum.find(&(&1.invite_email == invitee_email))

      assert invited_membership

      conn =
        conn
        |> recycle()
        |> delete("/company/memberships/#{invited_membership.id}")

      assert redirected_to(conn) == "/company"

      refute Enum.any?(
               Monetization.list_memberships(company.id),
               &(&1.id == invited_membership.id)
             )
    end

    test "company owner regains management access when owner membership row is missing", %{
      conn: conn
    } do
      owner = create_user!()
      Accounts.mark_email_verified!(owner.id)
      company = create_company!(owner)

      owner_conn = html_conn(conn, owner)

      owner_membership =
        Monetization.list_memberships(company.id)
        |> Enum.find(&(&1.user_id == owner.id and &1.role == "owner"))

      assert owner_membership

      assert {:ok, _removed} =
               owner_membership
               |> Ecto.Changeset.change(status: "removed", role: "member")
               |> Repo.update()

      assert Monetization.active_membership_for_user(company.id, owner.id) == nil

      body =
        owner_conn
        |> get("/company")
        |> html_response(200)

      assert body =~ ~s(name="subscription[plan]")
      assert body =~ ~s(name="membership[email]")

      restored_membership = Monetization.active_membership_for_user(company.id, owner.id)
      assert restored_membership
      assert restored_membership.role == "owner"
      assert restored_membership.status == "active"
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

    kbe_code =
      Repo.one(from(k in KbeCode, order_by: [asc: k.code], limit: 1)) ||
        Repo.insert!(%KbeCode{code: "99", description: "KBE 99"})

    knp_code =
      Repo.one(from(k in KnpCode, order_by: [asc: k.code], limit: 1)) ||
        Repo.insert!(%KnpCode{code: "999", description: "KNP 999"})

    %{bank: bank, kbe_code: kbe_code, knp_code: knp_code}
  end

  defp count_occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end

  defp html_conn(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{user_id: user.id})
    |> put_private(:plug_skip_csrf_protection, true)
    |> put_req_header("accept", "text/html")
  end
end
