defmodule EdocApiWeb.CoreUiLocalizationTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Acts
  alias EdocApi.Buyers

  setup %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, user: user, company: company, conn: conn}
  end

  describe "Russian browser UI" do
    test "invoice index renders localized headings and statuses", %{
      conn: conn,
      user: user,
      company: company
    } do
      _invoice = insert_invoice!(user, company)

      conn = get(browser_conn(conn, user, "ru"), "/invoices")
      body = html_response(conn, 200)

      assert body =~ "Счета"
      assert body =~ "Покупатель"
      assert body =~ "Черновик"
      refute body =~ ">Invoices<"
      refute body =~ ">Draft<"
    end

    test "contract creation page renders localized copy", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, _buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Тестовый покупатель",
          "bin_iin" => "060215385673"
        })

      conn = get(browser_conn(conn, user, "ru"), "/contracts/new")
      body = html_response(conn, 200)

      assert body =~ "Новый договор"
      assert body =~ "Данные договора"
      assert body =~ "Добавить нового покупателя"
      refute body =~ "New Contract"
      refute body =~ "Contract Details"
    end

    test "act index renders localized headings", %{conn: conn, user: user} do
      conn = get(browser_conn(conn, user, "ru"), "/acts")
      body = html_response(conn, 200)

      assert body =~ "Акты"
      assert body =~ "Номер"
      assert body =~ "Дата выставления"
      refute body =~ ">Acts<"
      refute body =~ ">Issue Date<"
    end

    test "act show replaces raw x in totals row with neutral label", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company)

      conn = get(browser_conn(conn, user, "ru"), "/acts/#{act.id}")
      body = html_response(conn, 200)

      assert body =~ "Не применяется"
      refute body =~ ~s(>x<)
    end

    test "invoice creation page localizes helper copy in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      create_company_bank_account!(company)

      {:ok, _buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Тестовый покупатель",
          "bin_iin" => "060215385673"
        })

      conn = get(browser_conn(conn, user, "kk"), "/invoices/new")
      body = html_response(conn, 200)

      assert body =~
               "Таңдалған келісімшарт сатып алушыны, банк шотын және позицияларды автоматты түрде толтырады."

      refute body =~ "Selecting a contract pre-fills buyer, bank account, and items."
    end

    test "company settings page localizes bank-account chrome", %{
      conn: conn,
      user: user,
      company: company
    } do
      create_company_bank_account!(company)

      conn = get(browser_conn(conn, user, "ru"), "/company")
      body = html_response(conn, 200)

      assert body =~ "Банковские счета"
      assert body =~ "Добавить банковский счет"
      refute body =~ ">Bank Accounts<"
      refute body =~ ">Add Bank Account<"
    end

    test "company shell falls back to localized menu label in Russian", %{
      conn: conn,
      user: user
    } do
      body = conn |> browser_conn(user, "ru") |> get("/company") |> html_response(200)
      assert body =~ ~r/<summary[^>]*>.*?<span>\s*Меню\s*<\/span>/s
      refute body =~ ~r/<a[^>]*aria-current="page"/
      refute body =~ ~r/<summary[^>]*>.*?<span>\s*Компания\s*<\/span>/s
    end

    test "company settings page localizes legal form label in Russian and Kazakh", %{
      conn: conn,
      user: user
    } do
      russian_conn = get(browser_conn(conn, user, "ru"), "/company")
      russian_body = html_response(russian_conn, 200)

      assert russian_body =~ "Правовая форма"
      refute russian_body =~ ~s(>Legal Form<)

      kazakh_conn = get(browser_conn(conn, user, "kk"), "/company")
      kazakh_body = html_response(kazakh_conn, 200)

      assert kazakh_body =~ "Құқықтық нысаны"
      refute kazakh_body =~ ~s(>Legal Form<)
    end

    test "company setup and settings pages localize address label", %{
      conn: conn,
      user: user
    } do
      fresh_user = create_user!()
      Accounts.mark_email_verified!(fresh_user.id)

      setup_conn = get(browser_conn(conn, fresh_user, "ru"), "/company/setup")
      setup_body = html_response(setup_conn, 200)

      assert setup_body =~ "Адрес"
      refute setup_body =~ ~s(>Address<)

      company = create_company!(user)

      settings_conn = get(browser_conn(conn, user, "ru"), "/company")
      settings_body = html_response(settings_conn, 200)

      assert company.address
      assert settings_body =~ "Адрес"
      refute settings_body =~ ~s(>Address<)
    end

    test "bank account update flash is localized in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      account = create_company_bank_account!(company)

      conn =
        browser_conn(conn, user, "ru")
        |> put("/company/bank-accounts/#{account.id}", %{
          "bank_account" => %{
            "label" => "Обновленный счет",
            "bank_id" => account.bank_id,
            "iban" => account.iban
          }
        })

      assert redirected_to(conn) == "/company"

      redirected_conn = get(recycle(conn), "/company")
      body = html_response(redirected_conn, 200)

      assert body =~ "Банковский счет успешно обновлен."
      refute body =~ "Bank account updated successfully."
    end
  end

  describe "Kazakh browser UI" do
    test "menu label is available in the gettext catalog for Russian and Kazakh" do
      assert Gettext.with_locale(EdocApiWeb.Gettext, "ru", fn ->
               Gettext.gettext(EdocApiWeb.Gettext, "Menu")
             end) == "Меню"

      assert Gettext.with_locale(EdocApiWeb.Gettext, "kk", fn ->
               Gettext.gettext(EdocApiWeb.Gettext, "Menu")
             end) == "Мәзір"
    end

    test "company settings page localizes bank table actions header in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      create_company_bank_account!(company)

      conn = get(browser_conn(conn, user, "kk"), "/company")
      body = html_response(conn, 200)

      assert body =~ "Әрекеттер"
      refute body =~ ~s(>Actions<)
    end

    test "company settings page localizes cancel actions in Kazakh", %{
      conn: conn,
      user: user
    } do
      conn = get(browser_conn(conn, user, "kk"), "/company")
      body = html_response(conn, 200)

      assert body =~ "Бас тарту"
      refute body =~ ~s(>Cancel<)
    end

    test "invoice shell trigger shows localized current-section label in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      _invoice = insert_invoice!(user, company)

      body = conn |> browser_conn(user, "kk") |> get("/invoices") |> html_response(200)
      assert body =~ ~r/<summary[^>]*>.*?<span>\s*Шоттар\s*<\/span>/s
      refute body =~ ~r/<summary[^>]*>.*?<span>\s*Invoices\s*<\/span>/s
    end

    test "company setup page renders Kazakh labels", %{conn: conn} do
      fresh_user = create_user!()
      Accounts.mark_email_verified!(fresh_user.id)

      conn = get(browser_conn(conn, fresh_user, "kk"), "/company/setup")
      body = html_response(conn, 200)

      assert body =~ "Компанияны баптау"
      assert body =~ "Компания атауы"

      assert body =~
               "Жұмысты бастау үшін компанияңыз бен банк шотыңыз туралы мәліметтерді енгізіңіз."

      assert body =~ "Мекенжай"
      assert body =~ "Банк шоты туралы ақпарат"
      assert body =~ "Банк"
      refute body =~ "Set Up Your Company"
      refute body =~ "Company Name"
      refute body =~ ~s(>Address<)
      refute body =~ ~s(>Bank Account Information<)
    end

    test "buyer validation flash is localized in Kazakh", %{conn: conn, user: user} do
      conn =
        browser_conn(conn, user, "kk")
        |> post("/buyers", %{
          "buyer" => %{
            "name" => "Жарамсыз сатып алушы",
            "bin_iin" => "123"
          }
        })

      body = html_response(conn, 200)

      assert body =~ "Жарамсыз БСН/ЖСН. Дұрыс 12 таңбалы БСН/ЖСН енгізіңіз."
      refute body =~ "Неверный БИН/ИИН"
      refute body =~ "must contain exactly 12 digits"
    end

    test "buyer index page localizes page chrome in Kazakh", %{
      conn: conn,
      user: user
    } do
      conn = get(browser_conn(conn, user, "kk"), "/buyers")
      body = html_response(conn, 200)

      assert body =~
               "Келісімшарттар мен шоттар үшін контрагенттерді (сатып алушыларды) басқарыңыз"

      assert body =~ "Әзірге сатып алушылар жоқ."
      refute body =~ "Manage your counterparties (buyers) for contracts and invoices"
      refute body =~ "No buyers"
    end

    test "company bank-account pages and flashes are localized in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      default_account = create_company_bank_account!(company, %{"label" => "Негізгі"})
      secondary_account = create_company_bank_account!(company, %{"label" => "Қосымша"})

      show_conn =
        get(browser_conn(conn, user, "kk"), "/company/bank-accounts/#{secondary_account.id}")

      show_body = html_response(show_conn, 200)

      assert show_body =~ "Банк шоты"
      assert show_body =~ "Банк"
      refute show_body =~ ">Bank Account<"
      refute show_body =~ ">Bank<"

      set_default_conn =
        browser_conn(conn, user, "kk")
        |> put("/company/bank-accounts/#{secondary_account.id}/set-default", %{})

      assert redirected_to(set_default_conn) == "/company"

      set_default_body =
        set_default_conn
        |> recycle()
        |> get("/company")
        |> html_response(200)

      assert set_default_body =~ "Негізгі банк шоты жаңартылды."
      refute set_default_body =~ "Default bank account updated."

      update_conn =
        browser_conn(conn, user, "kk")
        |> put("/company/bank-accounts/#{default_account.id}", %{
          "bank_account" => %{
            "label" => "Жаңартылған шот",
            "bank_id" => default_account.bank_id,
            "iban" => default_account.iban
          }
        })

      assert redirected_to(update_conn) == "/company"

      update_body =
        update_conn
        |> recycle()
        |> get("/company")
        |> html_response(200)

      assert update_body =~ "Банк шоты сәтті жаңартылды."
      refute update_body =~ "Bank account updated successfully."
    end
  end

  describe "Gettext catalog coverage" do
    test "remaining browser-ui translations are filled in both locales" do
      assert_catalog_translations("ru", %{
        "Back to Acts" => "Назад к актам",
        "Back to Company" => "Назад к компании",
        "Bank Accounts" => "Банковские счета",
        "Basis" => "Основание",
        "Create Act" => "Создать акт",
        "Create and manage contracts" => "Создавайте договоры и управляйте ими",
        "Create and manage invoices" => "Создавайте счета и управляйте ими",
        "Create your first contract" => "Создать первый договор",
        "Delete this draft contract?" => "Удалить этот черновик договора?",
        "Details" => "Подробности",
        "Label" => "Название",
        "No buyers" => "Покупателей пока нет.",
        "Ready to create contracts?" => "Готовы создавать договоры?",
        "View Contracts" => "Просмотреть договоры",
        "Yes" => "Да",
        "No" => "Нет"
      })

      assert_catalog_translations("kk", %{
        "Add Bank Account" => "Банк шотын қосу",
        "Add New Bank Account" => "Жаңа банк шотын қосу",
        "Actions" => "Әрекеттер",
        "Bank" => "Банк",
        "Bank Account" => "Банк шоты",
        "Bank account" => "Банк шоты",
        "Bank account added successfully." => "Банк шоты сәтті қосылды.",
        "Bank account not found." => "Банк шоты табылмады.",
        "Back to Company" => "Компанияға оралу",
        "Bank Accounts" => "Банк шоттары",
        "Default bank account updated." => "Негізгі банк шоты жаңартылды.",
        "Create your first contract" => "Алғашқы келісімшартты жасаңыз",
        "Details" => "Толығырақ",
        "Legal Form" => "Құқықтық нысаны",
        "Label" => "Атауы",
        "No buyers" => "Әзірге сатып алушылар жоқ.",
        "Ready to create contracts?" => "Келісімшарттар жасауға дайынсыз ба?",
        "View Contracts" => "Келісімшарттарды көру",
        "Yes" => "Иә",
        "No" => "Жоқ"
      })
    end
  end

  defp browser_conn(conn, user, locale) do
    conn
    |> Plug.Test.init_test_session(%{user_id: user.id, locale: locale})
    |> put_private(:plug_skip_csrf_protection, true)
    |> put_req_header("accept", "text/html")
  end

  defp assert_catalog_translations(locale, expected_translations) do
    content = File.read!(catalog_path(locale))

    Enum.each(expected_translations, fn {msgid, expected_msgstr} ->
      assert catalog_translation(content, msgid) == expected_msgstr
    end)
  end

  defp catalog_path(locale) do
    Path.join([File.cwd!(), "priv", "gettext", locale, "LC_MESSAGES", "default.po"])
  end

  defp catalog_translation(content, msgid) do
    escaped_msgid = Regex.escape(msgid)
    pattern = ~r/msgid "#{escaped_msgid}"\nmsgstr "((?:\\"|[^"])*)"/

    case Regex.run(pattern, content, capture: :all_but_first) do
      [msgstr] -> msgstr
      _ -> flunk("missing translation entry for #{inspect(msgid)}")
    end
  end

  defp create_act!(user, company) do
    {:ok, buyer} =
      Buyers.create_buyer_for_company(company.id, %{
        "name" => "Act Buyer",
        "bin_iin" => "101215385676",
        "email" => "act-buyer@example.com",
        "address" => "Buyer Address"
      })

    attrs = %{
      "issue_date" => Date.utc_today(),
      "buyer_id" => buyer.id,
      "buyer_address" => "Buyer Address",
      "items" => [
        %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
      ]
    }

    {:ok, act} = Acts.create_act_for_user(user.id, company.id, attrs)
    act
  end
end
