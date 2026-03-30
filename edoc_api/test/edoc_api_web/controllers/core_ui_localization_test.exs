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

    test "invoice overview localizes the new support copy in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      _invoice = insert_invoice!(user, company, %{status: "draft"})

      body =
        conn
        |> browser_conn(user, "ru")
        |> get("/invoices")
        |> html_response(200)

      assert body =~ "Реестр для черновиков, выставленных и оплаченных счетов."
      assert body =~ "xl:grid-cols-[minmax(0,1fr)_15rem]"
      assert body =~ "md:block"
      assert body =~ "min-w-44"
      refute body =~ ~s(class="hidden items-center justify-end gap-3 whitespace-nowrap md:flex")
      refute body =~ "Счета зависят от готовых данных компании и покупателя."
      refute body =~ "Track draft, issued, and paid invoices from one calm ledger view."
    end

    test "Russian catalog uses выставлен wording instead of выпущен", %{
      conn: conn,
      user: user,
      company: company
    } do
      assert Gettext.with_locale(EdocApiWeb.Gettext, "ru", fn ->
               Gettext.gettext(EdocApiWeb.Gettext, "Issued")
             end) == "Выставлен"

      assert Gettext.with_locale(EdocApiWeb.Gettext, "ru", fn ->
               Gettext.gettext(EdocApiWeb.Gettext, "Please select an issued contract.")
             end) == "Выберите выставленный договор."

      assert Gettext.with_locale(EdocApiWeb.Gettext, "ru", fn ->
               Gettext.gettext(EdocApiWeb.Gettext, "Select an issued contract...")
             end) == "Выберите выставленный договор..."

      _invoice = insert_invoice!(user, company, %{status: "issued", number: "INV-2026-2"})

      body =
        conn
        |> browser_conn(user, "ru")
        |> get("/invoices")
        |> html_response(200)

      assert body =~ "Выставлен"
      refute body =~ "Выпущен"
      refute body =~ "выпущенный договор"
    end

    test "invoice edit page localizes heading and remove controls in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_invoice_with_items!(user, company)

      body =
        conn
        |> browser_conn(user, "ru")
        |> get("/invoices/#{invoice.id}/edit")
        |> html_response(200)

      assert body =~ "Редактировать счет #{invoice.number}"
      assert body =~ "Дата выставления"
      assert body =~ "Срок оплаты"
      assert body =~ "Адрес покупателя"
      assert body =~ "Валюта"
      assert body =~ "Ставка НДС (%)"
      assert body =~ "Ед.изм"

      assert body =~
               ~r/<button type="button"[^>]*>\s*Удалить\s*<\/button>/

      refute body =~ "Edit Invoice"
      refute body =~ ~s(>Код<)
      refute body =~ ~s(>Remove<)
    end

    test "invoice show page localizes heading in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_invoice_with_items!(user, company)

      body =
        conn
        |> browser_conn(user, "ru")
        |> get("/invoices/#{invoice.id}")
        |> html_response(200)

      assert body =~ "<title>Счёт на оплату № #{invoice.number}</title>"
      assert body =~ ~r/<h1[^>]*>\s*Счёт на оплату № #{Regex.escape(invoice.number)}\s*<\/h1>/
      assert body =~ ~r/<button[^>]*>\s*Выставить\s*<\/button>/
      refute body =~ "<title>Invoice #{invoice.number}</title>"
      refute body =~ "Выпустить"
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
      assert body =~ "Позиции договора (Приложение 1)"
      assert body =~ "Наименование"
      assert body =~ "Количество"
      assert body =~ "Цена за единицу"
      assert body =~ ~s(placeholder="Алматы")
      assert body =~ ~s(placeholder="Описание позиции")
      assert body =~ ~s(data-required-message="Пожалуйста, заполните это поле.")
      assert body =~ ~s|oninvalid="this.setCustomValidity(this.dataset.requiredMessage)"|
      assert body =~ "Добавить нового покупателя"
      assert body =~ ~r/<summary[^>]*>.*?<span>\s*Договоры\s*<\/span>/s
      refute body =~ "New Contract"
      refute body =~ "Contract Details"
      refute body =~ "Contract items (Appendix 1)"
      refute body =~ ~s(placeholder="Almaty")
      refute body =~ ~s(placeholder="Item description")
      refute body =~ "Item name"
      refute body =~ "Quantity"
      refute body =~ "Unit price"
    end

    test "contract edit page localizes heading and item column in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      create_company_bank_account!(company)
      contract = create_contract!(company, %{"status" => "draft", "number" => "CON-EDIT-RU-1"})

      body =
        conn
        |> browser_conn(user, "ru")
        |> get("/contracts/#{contract.id}/edit")
        |> html_response(200)

      assert body =~ "Редактировать договор #{contract.number}"
      assert body =~ "Наименование"
      refute body =~ "Edit Contract"
      refute body =~ "Item name"
    end

    test "contract creation success flash and show heading are localized in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      create_company_bank_account!(company)

      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Тестовый покупатель",
          "bin_iin" => "060215385673"
        })

      create_conn =
        post(browser_conn(conn, user, "ru"), "/contracts", %{
          "contract" => %{
            "number" => "CON-RU-1",
            "issue_date" => "#{Date.utc_today()}",
            "buyer_id" => buyer.id,
            "city" => "Алматы"
          },
          "items" => %{
            "0" => %{
              "name" => "Услуга",
              "code" => "шт",
              "qty" => "1",
              "unit_price" => "1000.00"
            }
          },
          "action" => "draft"
        })

      assert redirected_to(create_conn) =~ "/contracts/"

      body =
        create_conn
        |> recycle()
        |> get(redirected_to(create_conn))
        |> html_response(200)

      assert body =~ "Договор создан успешно."
      assert body =~ ~r/<title>Договор № CON-RU-1<\/title>/
      assert body =~ ~r/<h1[^>]*>\s*Договор № CON-RU-1\s*<\/h1>/
      assert body =~ ~r/<button[^>]*>\s*Выставить\s*<\/button>/
      refute body =~ "Contract created successfully."
      refute body =~ "<title>Contract CON-RU-1</title>"
      refute body =~ "Выпустить"
    end

    test "contract update success flash is localized in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company, %{"status" => "draft", "number" => "CON-UPD-RU-1"})

      update_conn =
        put(browser_conn(conn, user, "ru"), "/contracts/#{contract.id}", %{
          "contract" => %{
            "number" => contract.number,
            "issue_date" => "#{contract.issue_date}",
            "city" => "Алматы"
          },
          "items" => %{
            "0" => %{
              "name" => "Дополнительная услуга",
              "code" => "шт",
              "qty" => "1",
              "unit_price" => "1000.00"
            }
          }
        })

      assert redirected_to(update_conn) == "/contracts/#{contract.id}"

      body =
        update_conn
        |> recycle()
        |> get("/contracts/#{contract.id}")
        |> html_response(200)

      assert body =~ "Договор успешно обновлен."
      refute body =~ "Contract updated successfully."
    end

    test "contract issue success flash is localized in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company, %{"status" => "draft", "number" => "CON-ISS-RU-1"})

      issue_conn = post(browser_conn(conn, user, "ru"), "/contracts/#{contract.id}/issue")

      assert redirected_to(issue_conn) == "/contracts/#{contract.id}"

      body =
        issue_conn
        |> recycle()
        |> get("/contracts/#{contract.id}")
        |> html_response(200)

      assert body =~ "Договор успешно выставлен."
      refute body =~ "Contract issued successfully."
    end

    test "contract issued page localizes signed actions in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company, %{"status" => "issued", "number" => "CON-SIGN-RU-1"})

      show_body =
        conn
        |> browser_conn(user, "ru")
        |> get("/contracts/#{contract.id}")
        |> html_response(200)

      index_body =
        conn
        |> browser_conn(user, "ru")
        |> get("/contracts")
        |> html_response(200)

      assert show_body =~ "Отметить как подписан"
      assert index_body =~ "Подписан"
      refute show_body =~ "Mark as Signed"
      refute index_body =~ ">Signed<"
    end

    test "buyer creation success flash is localized in Russian", %{
      conn: conn,
      user: user
    } do
      create_conn =
        post(browser_conn(conn, user, "ru"), "/buyers", %{
          "buyer" => %{
            "name" => "Тестовый покупатель",
            "bin_iin" => "060215385673"
          }
        })

      assert redirected_to(create_conn) == "/buyers"

      body =
        create_conn
        |> recycle()
        |> get("/buyers")
        |> html_response(200)

      assert body =~
               "Покупатель создан успешно. &quot;Тестовый покупатель&quot; готов к использованию в договорах и счетах."

      refute body =~ "Buyer created successfully."
      refute body =~ "is ready to use in contracts and invoices."
    end

    test "buyer invalid IBAN flash is localized and user-friendly in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Покупатель с IBAN",
          "bin_iin" => "080215385677"
        })

      bank_id =
        EdocApi.Payments.list_banks()
        |> List.first()
        |> Map.fetch!(:id)

      update_conn =
        browser_conn(conn, user, "ru")
        |> put("/buyers/#{buyer.id}", %{
          "buyer" => %{
            "name" => buyer.name,
            "bin_iin" => buyer.bin_iin,
            "bank_id" => bank_id,
            "iban" => "KZ961234567890123456"
          }
        })

      body = html_response(update_conn, 200)

      assert body =~
               "Проверьте номер IBAN. Он должен содержать ровно 20 буквенно-цифровых символов."

      refute body =~ "IBAN: has invalid checksum"
    end

    test "buyer update success flash is localized in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Покупатель для обновления",
          "bin_iin" => "080215385677"
        })

      update_conn =
        put(browser_conn(conn, user, "ru"), "/buyers/#{buyer.id}", %{
          "buyer" => %{
            "name" => "Обновлённый покупатель",
            "bin_iin" => buyer.bin_iin
          }
        })

      assert redirected_to(update_conn) == "/buyers"

      body =
        update_conn
        |> recycle()
        |> get("/buyers")
        |> html_response(200)

      assert body =~ "Покупатель успешно обновлен."
      refute body =~ "Buyer updated successfully."
    end

    test "buyer delete success flash is localized in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Покупатель для удаления",
          "bin_iin" => "060215385673"
        })

      delete_conn = delete(browser_conn(conn, user, "ru"), "/buyers/#{buyer.id}")

      assert redirected_to(delete_conn) == "/buyers"

      body =
        delete_conn
        |> recycle()
        |> get("/buyers")
        |> html_response(200)

      assert body =~ "Покупатель успешно удален."
      refute body =~ "Buyer deleted successfully."
    end

    test "contract delete success flash is localized and rendered once in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company, %{"status" => "draft", "number" => "DEL-RU-1"})

      delete_conn = delete(browser_conn(conn, user, "ru"), "/contracts/#{contract.id}")

      assert redirected_to(delete_conn) == "/contracts"

      body =
        delete_conn
        |> recycle()
        |> get("/contracts")
        |> html_response(200)

      assert body =~ "Договор успешно удален."
      assert length(Regex.scan(~r/Договор успешно удален\./, body)) == 1
      refute body =~ "Contract deleted successfully."
    end

    test "contracts index renders compact actions while preserving action colors", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company)

      body = conn |> browser_conn(user, "ru") |> get("/contracts") |> html_response(200)

      assert body =~ "min-w-44"
      assert body =~ "w-px whitespace-nowrap px-6 py-4 text-right"
      refute body =~ "inline-flex items-center gap-3"
      assert body =~ ~s(href="/contracts/#{contract.id}")

      assert body =~
               ~s(class="block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-blue-600 transition hover:bg-blue-50 hover:text-blue-900")

      assert body =~
               ~s(class="block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-green-600 transition hover:bg-green-50 hover:text-green-900")

      assert body =~
               ~s(class="block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-red-600 transition hover:bg-red-50 hover:text-red-900")
    end

    test "act index renders localized headings", %{conn: conn, user: user} do
      company = create_company!(user)
      _act = create_act!(user, company)

      conn = get(browser_conn(conn, user, "ru"), "/acts")
      body = html_response(conn, 200)

      assert body =~ "Акты"
      assert body =~ "Номер"
      assert body =~ "Дата выставления"
      assert body =~ ~r/<summary[^>]*>.*?<span>\s*Акты\s*<\/span>/s
      refute body =~ ">Acts<"
      refute body =~ ">Issue Date<"
    end

    test "acts index renders compact actions while preserving requested action colors", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company)

      body = conn |> browser_conn(user, "ru") |> get("/acts") |> html_response(200)

      assert body =~ "min-w-44"
      assert body =~ "w-px whitespace-nowrap px-6 py-4 text-right"
      assert body =~ "overflow-y-visible"
      assert body =~ "overflow-visible rounded-3xl border border-stone-200 bg-white shadow-sm"
      refute body =~ "text-blue-600 hover:text-blue-900 mr-4"
      assert body =~ ~s(href="/acts/#{act.id}")

      assert body =~
               ~s(class="block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-blue-600 transition hover:bg-blue-50 hover:text-blue-900")

      assert body =~
               ~s(class="block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-green-600 transition hover:bg-green-50 hover:text-green-900")

      assert body =~
               ~s(class="block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-red-700 transition hover:bg-red-50 hover:text-red-900")
    end

    test "act show keeps raw x in totals row", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company)

      conn = get(browser_conn(conn, user, "ru"), "/acts/#{act.id}")
      body = html_response(conn, 200)

      assert body =~ ~s(>x<)
      refute body =~ "Не применяется"
    end

    test "act show localizes the header title in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company)

      conn = get(browser_conn(conn, user, "ru"), "/acts/#{act.id}")
      body = html_response(conn, 200)

      assert body =~ "Акт № #{act.number}"
      refute body =~ "Act #{act.number}"
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

      assert body =~ ~r/<summary[^>]*>.*?<span>\s*Шоттар\s*<\/span>/s
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

    test "company settings page renders welcome flash once in Russian", %{
      conn: conn,
      user: user
    } do
      body =
        conn
        |> browser_conn(user, "ru")
        |> Phoenix.Controller.fetch_flash([])
        |> Phoenix.Controller.put_flash(:info, "Добро пожаловать!")
        |> get("/company")
        |> html_response(200)

      assert length(Regex.scan(~r/Добро пожаловать!/, body)) == 1
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

    test "company settings page shortens representative title label in Russian", %{
      conn: conn,
      user: user
    } do
      body = conn |> browser_conn(user, "ru") |> get("/company") |> html_response(200)

      assert body =~ "Должность"
      refute body =~ "Должность представителя"
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

    test "buyer edit page localizes heading and buyer-detail labels in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Русский покупатель",
          "bin_iin" => "060215385673"
        })

      body =
        conn |> browser_conn(user, "ru") |> get("/buyers/#{buyer.id}/edit") |> html_response(200)

      assert body =~ "Редактировать покупателя"
      assert body =~ "ФИО"
      assert body =~ "Должность"
      assert body =~ "Основание (полномочия)"
      assert body =~ "БИН/ИИН"
      refute body =~ "Edit Buyer"
      refute body =~ "ФИО директора"
      refute body =~ "Должность директора"
      refute body =~ "Basis (Authority)"
      refute body =~ ~s(>BIN/IIN<)
    end

    test "buyer show page shortens the director label in Russian", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Покупатель для просмотра",
          "bin_iin" => "101215385676"
        })

      body = conn |> browser_conn(user, "ru") |> get("/buyers/#{buyer.id}") |> html_response(200)

      assert body =~ "ФИО"
      refute body =~ "ФИО директора"
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
      assert body =~ "xl:grid-cols-[minmax(0,1fr)_15rem]"
      refute body =~ "Шоттар дайын сатып алушы мен компания деректеріне тәуелді."
      refute body =~ ~r/<summary[^>]*>.*?<span>\s*Invoices\s*<\/span>/s
    end

    test "invoice index localizes total heading and issued status in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      assert Gettext.with_locale(EdocApiWeb.Gettext, "kk", fn ->
               Gettext.gettext(EdocApiWeb.Gettext, "Total")
             end) == "Жалпы сома"

      assert Gettext.with_locale(EdocApiWeb.Gettext, "kk", fn ->
               Gettext.gettext(EdocApiWeb.Gettext, "Issued")
             end) == "Шығарылған"

      _invoice = insert_invoice!(user, company, %{status: "issued", number: "INV-2026-2"})

      body =
        conn
        |> browser_conn(user, "kk")
        |> get("/invoices")
        |> html_response(200)

      assert body =~ "Жалпы сома"
      assert body =~ "Шығарылған"
      refute body =~ ~s(>Total<)
      refute body =~ ~s(>Issued<)
    end

    test "invoice edit page localizes headings, status, fields, and remove controls in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_invoice_with_items!(user, company)

      body =
        conn
        |> browser_conn(user, "kk")
        |> get("/invoices/#{invoice.id}/edit")
        |> html_response(200)

      assert body =~ "Шотты өңдеу #{invoice.number}"
      assert body =~ "Мәртебе"
      assert body =~ "Жоба"
      assert body =~ "Шығарылған күні"
      assert body =~ "Төлеу мерзімі"
      assert body =~ "Сатып алушының мекенжайы"
      assert body =~ "Валюта"
      assert body =~ "ҚҚС мөлшерлемесі (%)"
      assert body =~ "Тармақ қосу"
      assert body =~ "Өлшем бірлігі"

      assert body =~
               ~r/<button type="button"[^>]*>\s*Жою\s*<\/button>/

      refute body =~ "Edit Invoice"
      refute body =~ ~s(>Код<)
      refute body =~ "Нобай"
      refute body =~ ~s(>Draft<)
      refute body =~ ~s(>Due date<)
      refute body =~ ~s(>Currency<)
      refute body =~ ~s(>Buyer address<)
      refute body =~ ~s(>Remove<)
    end

    test "invoice show page localizes heading in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      invoice = create_invoice_with_items!(user, company)

      body =
        conn
        |> browser_conn(user, "kk")
        |> get("/invoices/#{invoice.id}")
        |> html_response(200)

      assert body =~ "<title>Төлем шоты № #{invoice.number}</title>"
      assert body =~ ~r/<h1[^>]*>\s*Төлем шоты № #{Regex.escape(invoice.number)}\s*<\/h1>/
      refute body =~ "<title>Invoice #{invoice.number}</title>"
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

    test "buyer invalid IBAN flash is localized and user-friendly in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "IBAN бар сатып алушы",
          "bin_iin" => "080215385677"
        })

      bank_id =
        EdocApi.Payments.list_banks()
        |> List.first()
        |> Map.fetch!(:id)

      update_conn =
        browser_conn(conn, user, "kk")
        |> put("/buyers/#{buyer.id}", %{
          "buyer" => %{
            "name" => buyer.name,
            "bin_iin" => buyer.bin_iin,
            "bank_id" => bank_id,
            "iban" => "KZ961234567890123456"
          }
        })

      body = html_response(update_conn, 200)

      assert body =~
               "IBAN нөмірін тексеріңіз. Ол дәл 20 әріптік-сандық таңбадан тұруы керек."

      refute body =~ "IBAN: has invalid checksum"
    end

    test "buyer edit page localizes heading and buyer-detail labels in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Қазақ сатып алушы",
          "bin_iin" => "080215385677"
        })

      body =
        conn |> browser_conn(user, "kk") |> get("/buyers/#{buyer.id}/edit") |> html_response(200)

      assert body =~ ~r/<a[^>]*href="\/buyers"[^>]*>\s*&larr;\s*Сатып алушыларға оралу\s*<\/a>/
      assert body =~ "Сатып алушыны өңдеу"
      assert body =~ "Аты-жөні"
      assert body =~ "Лауазымы"
      assert body =~ "Негіздеме (өкілеттік)"
      assert body =~ "БСН/ЖСН"
      refute body =~ "Edit Buyer"
      refute body =~ "Back to Buyers"
      refute body =~ "Director Name"
      refute body =~ "Director Title"
      refute body =~ "Basis (Authority)"
      refute body =~ ~s(>BIN/IIN<)
    end

    test "buyer show page shortens the director label in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Сатып алушыны көру",
          "bin_iin" => "060215385673"
        })

      body = conn |> browser_conn(user, "kk") |> get("/buyers/#{buyer.id}") |> html_response(200)

      assert body =~ "Аты-жөні"
      refute body =~ ">Директор<"
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

    test "act show localizes the header title in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      act = create_act!(user, company)

      conn = get(browser_conn(conn, user, "kk"), "/acts/#{act.id}")
      body = html_response(conn, 200)

      assert body =~ "Акт № #{act.number}"
      refute body =~ "Act #{act.number}"
    end

    test "buyer creation success flash is localized in Kazakh", %{
      conn: conn,
      user: user
    } do
      create_conn =
        post(browser_conn(conn, user, "kk"), "/buyers", %{
          "buyer" => %{
            "name" => "Сынақ сатып алушысы",
            "bin_iin" => "060215385673"
          }
        })

      assert redirected_to(create_conn) == "/buyers"

      body =
        create_conn
        |> recycle()
        |> get("/buyers")
        |> html_response(200)

      assert body =~
               "Сатып алушы сәтті құрылды. &quot;Сынақ сатып алушысы&quot; келісімшарттар мен шоттарда пайдалануға дайын."

      refute body =~ "Buyer created successfully."
      refute body =~ "is ready to use in contracts and invoices."
    end

    test "buyer update success flash is localized in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Жаңартуға арналған сатып алушы",
          "bin_iin" => "080215385677"
        })

      update_conn =
        put(browser_conn(conn, user, "kk"), "/buyers/#{buyer.id}", %{
          "buyer" => %{
            "name" => "Жаңартылған сатып алушы",
            "bin_iin" => buyer.bin_iin
          }
        })

      assert redirected_to(update_conn) == "/buyers"

      body =
        update_conn
        |> recycle()
        |> get("/buyers")
        |> html_response(200)

      assert body =~ "Сатып алушы сәтті жаңартылды."
      refute body =~ "Buyer updated successfully."
    end

    test "buyer delete success flash is localized in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Жоюға арналған сатып алушы",
          "bin_iin" => "060215385673"
        })

      delete_conn = delete(browser_conn(conn, user, "kk"), "/buyers/#{buyer.id}")

      assert redirected_to(delete_conn) == "/buyers"

      body =
        delete_conn
        |> recycle()
        |> get("/buyers")
        |> html_response(200)

      assert body =~ "Сатып алушы сәтті жойылды."
      refute body =~ "Buyer deleted successfully."
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

    test "company bank-account delete action is localized in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      _default_account = create_company_bank_account!(company, %{"label" => "Негізгі"})
      secondary_account = create_company_bank_account!(company, %{"label" => "Қосымша"})

      body = conn |> browser_conn(user, "kk") |> get("/company") |> html_response(200)

      assert body =~ ~s(action="/company/bank-accounts/#{secondary_account.id}")
      assert body =~ "min-w-44"
      assert body =~ "Бас тарту"
      refute body =~ "whitespace-nowrap md:flex"
      refute body =~ ~s(>Delete<)
    end

    test "contract creation page renders localized item-table copy in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, _buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Тест сатып алушы",
          "bin_iin" => "060215385673"
        })

      conn = get(browser_conn(conn, user, "kk"), "/contracts/new")
      body = html_response(conn, 200)

      assert body =~ "Жаңа келісімшарт"
      assert body =~ "Келісімшарт тармақтары (1-қосымша)"
      assert body =~ "Тауар атауы"
      assert body =~ "Саны"
      assert body =~ "Бірлік бағасы"
      assert body =~ ~s(placeholder="Алматы")
      assert body =~ ~s(placeholder="Тармақ сипаттамасы")
      assert body =~ ~s(data-required-message="Осы өрісті толтырыңыз.")
      assert body =~ ~s|oninvalid="this.setCustomValidity(this.dataset.requiredMessage)"|
      refute body =~ "Contract items (Appendix 1)"
      refute body =~ ~s(placeholder="Almaty")
      refute body =~ ~s(placeholder="Item description")
      refute body =~ "Item name"
      refute body =~ "Quantity"
      refute body =~ "Unit price"
    end

    test "contract edit page localizes heading in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      create_company_bank_account!(company)
      contract = create_contract!(company, %{"status" => "draft", "number" => "CON-EDIT-KK-1"})

      body =
        conn
        |> browser_conn(user, "kk")
        |> get("/contracts/#{contract.id}/edit")
        |> html_response(200)

      assert body =~ "Келісімшартты өңдеу #{contract.number}"
      refute body =~ "Edit Contract"
    end

    test "contract creation success flash and show heading are localized in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      create_company_bank_account!(company)

      {:ok, buyer} =
        Buyers.create_buyer_for_company(company.id, %{
          "name" => "Тест сатып алушы",
          "bin_iin" => "060215385673"
        })

      create_conn =
        post(browser_conn(conn, user, "kk"), "/contracts", %{
          "contract" => %{
            "number" => "CON-KK-1",
            "issue_date" => "#{Date.utc_today()}",
            "buyer_id" => buyer.id,
            "city" => "Алматы"
          },
          "items" => %{
            "0" => %{
              "name" => "Қызмет",
              "code" => "шт",
              "qty" => "1",
              "unit_price" => "1000.00"
            }
          },
          "action" => "draft"
        })

      assert redirected_to(create_conn) =~ "/contracts/"

      body =
        create_conn
        |> recycle()
        |> get(redirected_to(create_conn))
        |> html_response(200)

      assert body =~ "Келісімшарт сәтті құрылды."
      assert body =~ ~r/<title>Келісімшарт № CON-KK-1<\/title>/
      assert body =~ ~r/<h1[^>]*>\s*Келісімшарт № CON-KK-1\s*<\/h1>/
      assert body =~ "Келісімшарттарға оралу"
      assert body =~ ~r/<button[^>]*>\s*Шығару\s*<\/button>/
      refute body =~ "Contract created successfully."
      refute body =~ "<title>Contract CON-KK-1</title>"
      refute body =~ "Back to Contracts"
      refute body =~ ~s(>Issue<)
    end

    test "contract update success flash is localized in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company, %{"status" => "draft", "number" => "CON-UPD-KK-1"})

      update_conn =
        put(browser_conn(conn, user, "kk"), "/contracts/#{contract.id}", %{
          "contract" => %{
            "number" => contract.number,
            "issue_date" => "#{contract.issue_date}",
            "city" => "Алматы"
          },
          "items" => %{
            "0" => %{
              "name" => "Қосымша қызмет",
              "code" => "шт",
              "qty" => "1",
              "unit_price" => "1000.00"
            }
          }
        })

      assert redirected_to(update_conn) == "/contracts/#{contract.id}"

      body =
        update_conn
        |> recycle()
        |> get("/contracts/#{contract.id}")
        |> html_response(200)

      assert body =~ "Келісімшарт сәтті жаңартылды."
      refute body =~ "Contract updated successfully."
    end

    test "contract issue success flash is localized in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company, %{"status" => "draft", "number" => "CON-ISS-KK-1"})

      issue_conn = post(browser_conn(conn, user, "kk"), "/contracts/#{contract.id}/issue")

      assert redirected_to(issue_conn) == "/contracts/#{contract.id}"

      body =
        issue_conn
        |> recycle()
        |> get("/contracts/#{contract.id}")
        |> html_response(200)

      assert body =~ "Келісімшарт сәтті шығарылды."
      refute body =~ "Contract issued successfully."
    end

    test "contract issued page localizes signed actions in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company, %{"status" => "issued", "number" => "CON-SIGN-KK-1"})

      show_body =
        conn
        |> browser_conn(user, "kk")
        |> get("/contracts/#{contract.id}")
        |> html_response(200)

      index_body =
        conn
        |> browser_conn(user, "kk")
        |> get("/contracts")
        |> html_response(200)

      assert show_body =~ "Қол қойылған деп белгілеу"
      assert index_body =~ "Қол қойылған"
      refute show_body =~ "Mark as Signed"
      refute index_body =~ ">Signed<"
    end

    test "contract delete success flash is localized and rendered once in Kazakh", %{
      conn: conn,
      user: user,
      company: company
    } do
      contract = create_contract!(company, %{"status" => "draft", "number" => "DEL-KK-1"})

      delete_conn = delete(browser_conn(conn, user, "kk"), "/contracts/#{contract.id}")

      assert redirected_to(delete_conn) == "/contracts"

      body =
        delete_conn
        |> recycle()
        |> get("/contracts")
        |> html_response(200)

      assert body =~ "Келісімшарт сәтті жойылды."
      assert length(Regex.scan(~r/Келісімшарт сәтті жойылды\./, body)) == 1
      refute body =~ "Contract deleted successfully."
    end
  end

  describe "Gettext catalog coverage" do
    test "remaining browser-ui translations are filled in both locales" do
      assert_catalog_translations("ru", %{
        "Act %{number}" => "Акт № %{number}",
        "Almaty" => "Алматы",
        "Back to Acts" => "Назад к актам",
        "Back to Company" => "Назад к компании",
        "Bank Accounts" => "Банковские счета",
        "Basis" => "Основание",
        "Buyer created successfully. %{name} is ready to use in contracts and invoices." =>
          "Покупатель создан успешно. %{name} готов к использованию в договорах и счетах.",
        "Buyer deleted successfully." => "Покупатель успешно удален.",
        "Buyer updated successfully." => "Покупатель успешно обновлен.",
        "Check the IBAN number. It must be exactly 20 alphanumeric characters." =>
          "Проверьте номер IBAN. Он должен содержать ровно 20 буквенно-цифровых символов.",
        "Buyers are used for contracts and invoices." =>
          "Покупатели используются для договоров и счетов.",
        "Keep buyer details current before creating contracts and invoices." =>
          "Держите данные покупателей актуальными перед созданием договоров и счетов.",
        "Create Act" => "Создать акт",
        "Create and manage contracts" => "Создавайте договоры и управляйте ими",
        "Create and manage invoices" => "Создавайте счета и управляйте ими",
        "Create your first contract" => "Создать первый договор",
        "Contract %{number}" => "Договор № %{number}",
        "Contract has already been marked as signed." => "Договор уже отмечен как подписанный.",
        "Contract created successfully." => "Договор создан успешно.",
        "Contract deleted successfully." => "Договор успешно удален.",
        "Contract items (Appendix 1)" => "Позиции договора (Приложение 1)",
        "Contract marked as signed." => "Договор отмечен как подписанный.",
        "Delete this draft contract?" => "Удалить этот черновик договора?",
        "Details" => "Подробности",
        "Item description" => "Описание позиции",
        "Item name" => "Наименование",
        "Label" => "Название",
        "Mark as Signed" => "Отметить как подписан",
        "No buyers" => "Покупателей пока нет.",
        "Only issued contracts can be marked as signed." =>
          "Только выставленные договоры можно отметить как подписанные.",
        "Please fill out this field." => "Пожалуйста, заполните это поле.",
        "Quantity" => "Количество",
        "Ready to create contracts?" => "Готовы создавать договоры?",
        "Signed" => "Подписан",
        "Unit price" => "Цена за единицу",
        "View Contracts" => "Просмотреть договоры",
        "Yes" => "Да",
        "No" => "Нет"
      })

      assert_catalog_translations("kk", %{
        "Act %{number}" => "Акт № %{number}",
        "Add Bank Account" => "Банк шотын қосу",
        "Add New Bank Account" => "Жаңа банк шотын қосу",
        "Almaty" => "Алматы",
        "Actions" => "Әрекеттер",
        "Bank" => "Банк",
        "Bank Account" => "Банк шоты",
        "Bank account" => "Банк шоты",
        "Bank account added successfully." => "Банк шоты сәтті қосылды.",
        "Bank account not found." => "Банк шоты табылмады.",
        "Back to Buyers" => "Сатып алушыларға оралу",
        "Back to Company" => "Компанияға оралу",
        "Bank Accounts" => "Банк шоттары",
        "Buyer created successfully. %{name} is ready to use in contracts and invoices." =>
          "Сатып алушы сәтті құрылды. %{name} келісімшарттар мен шоттарда пайдалануға дайын.",
        "Buyer deleted successfully." => "Сатып алушы сәтті жойылды.",
        "Buyer updated successfully." => "Сатып алушы сәтті жаңартылды.",
        "Check the IBAN number. It must be exactly 20 alphanumeric characters." =>
          "IBAN нөмірін тексеріңіз. Ол дәл 20 әріптік-сандық таңбадан тұруы керек.",
        "Buyers are used for contracts and invoices." =>
          "Сатып алушылар келісімшарттар мен шоттар үшін пайдаланылады.",
        "Contract %{number}" => "Келісімшарт № %{number}",
        "Contract has already been marked as signed." =>
          "Келісімшарт қол қойылған деп бұрыннан белгіленген.",
        "Contract created successfully." => "Келісімшарт сәтті құрылды.",
        "Contract deleted successfully." => "Келісімшарт сәтті жойылды.",
        "Contract items (Appendix 1)" => "Келісімшарт тармақтары (1-қосымша)",
        "Contract marked as signed." => "Келісімшарт қол қойылған деп белгіленді.",
        "Draft" => "Жоба",
        "Keep buyer details current before creating contracts and invoices." =>
          "Келісімшарттар мен шоттарды жасамас бұрын сатып алушы деректерін өзекті күйде ұстаңыз.",
        "Default bank account updated." => "Негізгі банк шоты жаңартылды.",
        "Create your first contract" => "Алғашқы келісімшартты жасаңыз",
        "Details" => "Толығырақ",
        "Item description" => "Тармақ сипаттамасы",
        "Item name" => "Тауар атауы",
        "Legal Form" => "Құқықтық нысаны",
        "Label" => "Атауы",
        "Mark as Signed" => "Қол қойылған деп белгілеу",
        "No buyers" => "Әзірге сатып алушылар жоқ.",
        "Only issued contracts can be marked as signed." =>
          "Тек шығарылған келісімшарттарды қол қойылған деп белгілеуге болады.",
        "Please fill out this field." => "Осы өрісті толтырыңыз.",
        "Quantity" => "Саны",
        "Ready to create contracts?" => "Келісімшарттар жасауға дайынсыз ба?",
        "Signed" => "Қол қойылған",
        "Unit price" => "Бірлік бағасы",
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
