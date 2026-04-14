defmodule EdocApiWeb.WorkspaceOverviewUiTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures
  import Phoenix.LiveViewTest

  test "invoice index marks invoices nav active in the workspace shell", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    _draft = insert_invoice!(user, company, %{status: "draft", number: nil})
    _issued = insert_invoice!(user, company, %{status: "issued", number: "INV-2"})

    body =
      conn
      |> browser_conn(user, "en")
      |> get("/invoices")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/invoices"[^>]*aria-current="page"/
    assert body =~ ~s(action="/logout")
    refute body =~ ~r/<a[^>]*href="\/buyers"[^>]*aria-current="page"/
  end

  test "buyer edit keeps buyers nav active in the workspace shell", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Acme Buyer",
        "bin_iin" => "060215385673"
      })

    body =
      conn
      |> browser_conn(user, "en")
      |> get("/buyers/#{buyer.id}/edit")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/buyers"[^>]*aria-current="page"/
    refute body =~ ~r/<a[^>]*href="\/invoices"[^>]*aria-current="page"/
  end

  test "workspace navbar inactive links use black text classes", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    _invoice = insert_invoice!(user, company, %{status: "draft", number: nil})

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/buyers"[^>]*class="[^"]*dark:text-black[^"]*"/
    assert body =~ ~r/<a[^>]*href="\/contracts"[^>]*class="[^"]*dark:text-black[^"]*"/
    assert body =~ ~s|html[data-theme="dark"] .workspace-nav-link-inactive|
  end

  test "workspace locale and account controls include dark contrast fallback hooks", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    _company = create_company!(user)

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/company")
      |> html_response(200)

    assert body =~ "workspace-locale-inactive"
    assert body =~ "workspace-account-email"
    assert body =~ "workspace-account-logout"
    assert body =~ ~r/<a[^>]*class="[^"]*workspace-locale-inactive[^"]*"/
    assert body =~ ~r/<a[^>]*class="[^"]*workspace-account-email[^"]*"/
    assert body =~ ~r/<button[^>]*class="[^"]*workspace-account-logout[^"]*"/
    assert body =~ ~s|html[data-theme="dark"] .workspace-locale-inactive|
    assert body =~ ~s|html[data-theme="dark"] .workspace-account-email|
    assert body =~ ~s|html[data-theme="dark"] .workspace-account-logout|
  end

  test "company page keeps company nav active with shared styling", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    _company = create_company!(user)

    body =
      conn
      |> browser_conn(user, "en")
      |> get("/company")
      |> html_response(200)

    assert body =~
             ~r/<a[^>]*href="\/company"[^>]*aria-current="page"[^>]*class="[^"]*rounded-full[^"]*bg-white[^"]*shadow-sm[^"]*ring-1[^"]*"/

    refute body =~ ~r/<a[^>]*href="\/acts"[^>]*aria-current="page"/
  end

  test "company page renders theme bootstrap and workspace toggle controls", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    _company = create_company!(user)

    body =
      conn
      |> browser_conn(user, "en")
      |> get("/company")
      |> html_response(200)

    assert body =~ ~s(meta name="color-scheme" content="light dark")
    assert body =~ ~s|window.localStorage.getItem('edoc_theme')|
    assert body =~ ~s|window.toggleWorkspaceTheme = function()|
    assert body =~ ~s|root.setAttribute('data-theme', theme)|
    assert body =~ ~s|darkMode: "class"|
    assert body =~ ~s(data-theme-toggle)
    assert body =~ ~s(data-theme-label)
    refute body =~ ">Theme<"
    assert body =~ ~s|html[data-theme="dark"]|
    assert body =~ ~s(data-workspace-theme-root)
    assert body =~ "dark:bg-slate-950"
    assert body =~ "dark:bg-slate-900"
    refute body =~ ~s|html[data-theme="dark"] .text-gray-800|
  end

  test "company page includes dark-theme fallback palette overrides", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    _company = create_company!(user)

    body =
      conn
      |> browser_conn(user, "en")
      |> get("/company")
      |> html_response(200)

    assert body =~ ~s|html[data-theme="dark"] body[data-workspace-theme-root]|
    assert body =~ ~s|html[data-theme="dark"] .bg-white|
    assert body =~ ~s|html[data-theme="dark"] .text-gray-900|
  end

  test "company subscription summary cards use high-contrast text classes", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    _company = create_company!(user)

    body =
      conn
      |> browser_conn(user, "en")
      |> get("/company")
      |> html_response(200)

    assert length(Regex.scan(~r/text-sm font-medium text-gray-900 dark:text-slate-100/, body)) >=
             3

    assert body =~ ~s|mt-2 text-2xl font-semibold text-gray-900 dark:text-slate-100|
    assert body =~ ~s|mt-2 text-sm font-medium text-gray-900 dark:text-slate-100|
  end

  test "company team rows include dark hover fallback styling hook", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    _company = create_company!(user)

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/company")
      |> html_response(200)

    assert body =~ "company-team-row"
    assert body =~ ~s|html[data-theme="dark"] .company-team-row:hover|
  end

  test "company bank account rows include dark hover fallback styling hook", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    _company = create_company!(user)

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/company")
      |> html_response(200)

    assert body =~ "company-bank-row"
    assert body =~ ~s|html[data-theme="dark"] .company-bank-row:hover|
  end

  test "company member warning blocks include dark high-contrast fallback styling hook", %{
    conn: conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    member_user = create_user!(%{"email" => "company-member-warning-ui@example.com"})
    EdocApi.Accounts.mark_email_verified!(member_user.id)

    {:ok, _invite} =
      EdocApi.Monetization.invite_member(company.id, %{
        "email" => member_user.email,
        "role" => "member"
      })

    EdocApi.Monetization.accept_pending_memberships_for_user(member_user)

    body =
      conn
      |> browser_conn(member_user, "ru")
      |> get("/company")
      |> html_response(200)

    assert length(Regex.scan(~r/company-member-warning/, body)) >= 2
    assert body =~ ~s|html[data-theme="dark"] .company-member-warning|
  end

  test "invoice overview renders corrected table columns and derived counts", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    _draft =
      insert_invoice!(user, company, %{
        status: "draft",
        number: nil,
        total: Decimal.new("100.00"),
        issue_date: nil
      })

    _issued =
      insert_invoice!(user, company, %{
        status: "issued",
        number: "INV-2026-2",
        total: Decimal.new("200.00")
      })

    _paid =
      insert_invoice!(user, company, %{
        status: "paid",
        number: "INV-2026-3",
        total: Decimal.new("300.00")
      })

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices")
      |> html_response(200)

    assert body =~ "INV-2026-2"
    assert body =~ "100.00 KZT"
    assert body =~ "xl:grid-cols-[minmax(0,1fr)_15rem]"
    assert body =~ ~r/<td[^>]*>\s*-\s*<\/td>/
    assert body =~ "Обзор"
    assert body =~ "Черновики"
    assert body =~ ">1<"
    assert body =~ "Выставленные счета"
    assert body =~ "Оплаченные счета"
    assert body =~ "overflow-y-visible"
    assert body =~ "overflow-hidden rounded-3xl border border-stone-200 bg-white shadow-sm"
    refute body =~ "Счета зависят от готовых данных компании и покупателя."
  end

  test "invoice overview empty state uses the shared CTA surface", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    _company = create_company!(user)

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices")
      |> html_response(200)

    assert body =~ "Счетов пока нет."
    assert body =~ "Создайте первый счет, когда данные компании и покупателя будут готовы."
    assert body =~ ~s(href="/invoices/new")
    refute body =~ "Черновики"
    refute body =~ "xl:grid-cols-[minmax(0,1fr)_18rem]"
  end

  test "buyers overview replaces the detached callout with an integrated support panel", %{
    conn: conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, _buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Acme Buyer",
        "bin_iin" => "080215385677",
        "city" => "Алматы",
        "email" => "buyer@example.com"
      })

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/buyers")
      |> html_response(200)

    assert body =~ "Алматы"
    assert body =~ "buyer@example.com"
    assert body =~ ">1<"
    assert body =~ "Покупатели используются для договоров и счетов."
    assert body =~ "Держите данные покупателей актуальными перед созданием договоров и счетов."
    assert body =~ "Просмотреть договоры"
    assert body =~ "Действия"
    assert body =~ "w-px whitespace-nowrap px-6 py-4 text-right"
    assert body =~ "min-w-44"
    refute body =~ "whitespace-nowrap md:flex"
    refute body =~ "Назад к компании"
  end

  test "buyers overview empty state keeps one primary action and omits the contracts link", %{
    conn: conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    _company = create_company!(user)

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/buyers")
      |> html_response(200)

    assert body =~ "Покупателей пока нет."
    assert body =~ ~s(href="/buyers/new")
    refute body =~ "Просмотреть договоры"
  end

  test "contracts overview renders status counts in a right-side panel", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    _draft =
      create_contract!(company, %{
        "status" => "draft",
        "number" => "C-1",
        "buyer_name" => "Draft Buyer"
      })

    _issued =
      create_contract!(company, %{
        "status" => "issued",
        "number" => "C-2",
        "buyer_name" => "Issued Buyer"
      })

    _signed =
      create_contract!(company, %{
        "status" => "signed",
        "number" => "C-3",
        "buyer_name" => "Signed Buyer"
      })

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts")
      |> html_response(200)

    assert body =~ "Обзор"
    assert body =~ "Черновики договоров"
    assert body =~ "Выставленные договоры"
    assert body =~ "Подписанные договоры"
    assert body =~ "Покупатель"
    assert body =~ "Draft Buyer"
    assert body =~ "Issued Buyer"
    assert body =~ "Signed Buyer"
    assert body =~ "xl:grid-cols-[minmax(0,1fr)_15rem]"
    assert body =~ "overflow-y-visible"
    assert body =~ "overflow-hidden rounded-3xl border border-stone-200 bg-white shadow-sm"
    assert body =~ ~r/>1<\/dd>/
  end

  test "contracts overview shows buyer names for buyer-backed contracts", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Overview Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, _contract} =
      EdocApi.Core.create_contract_for_user(user.id, %{
        "number" => "C-REAL-1",
        "issue_date" => Date.utc_today(),
        "buyer_id" => buyer.id,
        "status" => "issued"
      })

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts")
      |> html_response(200)

    assert body =~ "Покупатель"
    assert body =~ "Overview Buyer"
  end

  test "contracts overview exposes a signed action for issued contracts", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    _draft = create_contract!(company, %{"status" => "draft", "number" => "C-DRAFT-1"})
    issued = create_contract!(company, %{"status" => "issued", "number" => "C-ISS-1"})

    body =
      conn
      |> browser_conn(user, "en")
      |> get("/contracts")
      |> html_response(200)

    assert body =~ ~s(action="/contracts/#{issued.id}/sign" method="post")
  end

  test "signed contract show page renders watermark", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    contract = create_contract!(company, %{"status" => "signed", "number" => "C-SIGNED-1"})

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts/#{contract.id}")
      |> html_response(200)

    assert body =~ "Подписан - Қол қойылған"
    assert body =~ "signed-watermark"
  end

  test "document show pages include explicit dark-mode contrast hooks for preview surfaces", %{
    conn: conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    invoice = insert_invoice!(user, company, %{status: "draft", number: "INV-DARK-1"})
    contract = create_contract!(company, %{"status" => "draft", "number" => "C-DARK-1"})

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, act} = create_act_for_overview(user, company, buyer, "draft")

    invoice_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/#{invoice.id}")
      |> html_response(200)

    contract_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts/#{contract.id}")
      |> html_response(200)

    act_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/#{act.id}")
      |> html_response(200)

    for body <- [invoice_body, contract_body, act_body] do
      assert body =~ ~s|html[data-theme="dark"] .workspace-document-preview-surface|
      assert body =~ ~s|html[data-theme="dark"] .workspace-document-shell|
    end

    assert invoice_body =~ ~r/<section[^>]*class="[^"]*workspace-document-shell[^"]*"/
    assert invoice_body =~ ~r/<div[^>]*class="[^"]*workspace-document-preview-surface[^"]*"/
    assert contract_body =~ ~r/<section[^>]*class="[^"]*workspace-document-shell[^"]*"/
    assert contract_body =~ ~r/<div[^>]*class="[^"]*workspace-document-preview-surface[^"]*"/
    assert act_body =~ ~r/<section[^>]*class="[^"]*workspace-document-shell[^"]*"/
    assert act_body =~ ~r/<div[^>]*class="[^"]*workspace-document-preview-surface[^"]*"/
  end

  test "acts overview exposes a signed action for issued acts", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, _draft} = create_act_for_overview(user, company, buyer, "draft")
    {:ok, issued} = create_act_for_overview(user, company, buyer, "issued")

    body =
      conn
      |> browser_conn(user, "en")
      |> get("/acts")
      |> html_response(200)

    assert body =~ ~s(action="/acts/#{issued.id}/sign" method="post")
  end

  test "act show renders sign action for issued acts and watermark for signed acts", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, issued} = create_act_for_overview(user, company, buyer, "issued")

    issued_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/#{issued.id}")
      |> html_response(200)

    assert issued_body =~ ~s(action="/acts/#{issued.id}/sign" method="post")

    {:ok, signed} = create_act_for_overview(user, company, buyer, "signed")

    signed_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/#{signed.id}")
      |> html_response(200)

    assert signed_body =~ "Подписан - Қол қойылған"
    assert signed_body =~ "signed-watermark"
    assert signed_body =~ "top: 45%;"
    assert signed_body =~ "left: 50%;"
    assert signed_body =~ "transform: translate(-50%, -50%) rotate(-24deg);"
    refute signed_body =~ "border: 6px solid"
    refute signed_body =~ "padding: 18px 28px"
  end

  test "act show exposes issue action for draft acts", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, draft} = create_act_for_overview(user, company, buyer, "draft")

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/#{draft.id}")
      |> html_response(200)

    assert body =~ ~s(action="/acts/#{draft.id}/issue" method="post")
    refute body =~ ~s(action="/acts/#{draft.id}/sign" method="post")
  end

  test "acts overview renders status counts in a right-side panel", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, draft} = create_act_for_overview(user, company, buyer, "draft")
    {:ok, issued} = create_act_for_overview(user, company, buyer, "issued")
    {:ok, _signed} = create_act_for_overview(user, company, buyer, "signed")

    assert draft.status == "draft"
    assert issued.status == "issued"

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts")
      |> html_response(200)

    assert body =~ "Обзор"
    assert body =~ "Черновики актов"
    assert body =~ "Выставленные акты"
    assert body =~ "Подписанные акты"
    assert body =~ "xl:grid-cols-[minmax(0,1fr)_15rem]"
    assert body =~ ~r/>1<\/dd>/
  end

  test "overview side panels use explicit dark-mode contrast classes across workspace index pages",
       %{
         conn: conn
       } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    _invoice = insert_invoice!(user, company, %{status: "draft", number: nil})
    _contract = create_contract!(company, %{"status" => "draft", "number" => "C-OV-1"})

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Overview Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, _act} = create_act_for_overview(user, company, buyer, "draft")

    {:ok, _buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Buyer Overview",
        "bin_iin" => "060215385673"
      })

    invoice_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices")
      |> html_response(200)

    contract_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts")
      |> html_response(200)

    act_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts")
      |> html_response(200)

    buyer_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/buyers")
      |> html_response(200)

    for body <- [invoice_body, contract_body, act_body, buyer_body] do
      assert body =~ "workspace-support-panel"
      assert body =~ "dark:bg-slate-900/95"
      assert body =~ "dark:border-slate-700"
      assert body =~ "dark:text-slate-100"
      assert body =~ "dark:text-slate-200"
      assert body =~ ~s|html[data-theme="dark"] .workspace-support-panel|
    end
  end

  test "workspace overview tables render fixed upward action overlays above short tables", %{
    conn: conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    _invoice = insert_invoice!(user, company, %{status: "draft", number: nil})
    _contract = create_contract!(company, %{"status" => "draft", "number" => "C-1"})

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, _act} = create_act_for_overview(user, company, buyer, "draft")

    invoice_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices")
      |> html_response(200)

    contract_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts")
      |> html_response(200)

    act_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts")
      |> html_response(200)

    assert invoice_body =~
             "overflow-hidden rounded-3xl border border-stone-200 bg-white shadow-sm"

    assert invoice_body =~ "overflow-x-auto"

    assert invoice_body =~ "relative overflow-visible w-px whitespace-nowrap px-6 py-4 text-right"
    assert invoice_body =~ "data-row-actions-menu"
    assert invoice_body =~ "fixed left-0 top-0 z-[80]"
    assert invoice_body =~ "ontoggle=\"window.positionWorkspaceRowActions"

    assert contract_body =~
             "overflow-hidden rounded-3xl border border-stone-200 bg-white shadow-sm"

    assert contract_body =~ "overflow-x-auto"

    assert contract_body =~
             "relative overflow-visible w-px whitespace-nowrap px-6 py-4 text-right"

    assert contract_body =~ "data-row-actions-menu"
    assert contract_body =~ "fixed left-0 top-0 z-[80]"
    assert contract_body =~ "ontoggle=\"window.positionWorkspaceRowActions"

    assert act_body =~ "overflow-hidden rounded-3xl border border-stone-200 bg-white shadow-sm"
    assert act_body =~ "overflow-x-auto"

    assert act_body =~ "relative overflow-visible w-px whitespace-nowrap px-6 py-4 text-right"
    assert act_body =~ "data-row-actions-menu"
    assert act_body =~ "fixed left-0 top-0 z-[80]"
    assert act_body =~ "ontoggle=\"window.positionWorkspaceRowActions"
  end

  test "workspace index table headings include explicit dark-mode contrast hooks", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    _invoice = insert_invoice!(user, company, %{status: "draft", number: nil})
    _contract = create_contract!(company, %{"status" => "draft", "number" => "C-HEAD-1"})

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Headings Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, _act} = create_act_for_overview(user, company, buyer, "draft")

    invoice_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices")
      |> html_response(200)

    contract_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts")
      |> html_response(200)

    act_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts")
      |> html_response(200)

    buyer_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/buyers")
      |> html_response(200)

    for body <- [invoice_body, contract_body, act_body, buyer_body] do
      assert body =~ "workspace-table-head-surface"
      assert body =~ "workspace-table-heading"
      assert body =~ ~s|html[data-theme="dark"] .workspace-table-heading|
      assert body =~ ~s|html[data-theme="dark"] .workspace-table-head-surface|
    end
  end

  test "invoice and contract edit row-actions are explicitly marked as success tone like buyers",
       %{conn: _conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    invoice = insert_invoice!(user, company, %{status: "draft", number: nil})
    contract = create_contract!(company, %{"status" => "draft", "number" => "C-EDIT-TONE-1"})

    invoice_edit_action =
      invoice
      |> EdocApiWeb.InvoicesHTML.row_actions()
      |> Map.fetch!(:secondary)
      |> Enum.find(&(&1[:href] == "/invoices/#{invoice.id}/edit"))

    contract_edit_action =
      contract
      |> EdocApiWeb.ContractHTML.contract_row_actions()
      |> Map.fetch!(:secondary)
      |> Enum.find(&(&1[:href] == "/contracts/#{contract.id}/edit"))

    assert invoice_edit_action[:tone] == :success
    assert contract_edit_action[:tone] == :success
  end

  test "workspace index table rows include shared dark-mode hover hook", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    _invoice = insert_invoice!(user, company, %{status: "draft", number: nil})
    _contract = create_contract!(company, %{"status" => "draft", "number" => "C-HOVER-1"})

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Hover Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, _act} = create_act_for_overview(user, company, buyer, "draft")

    invoice_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices")
      |> html_response(200)

    contract_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts")
      |> html_response(200)

    act_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts")
      |> html_response(200)

    buyer_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/buyers")
      |> html_response(200)

    for body <- [invoice_body, contract_body, act_body, buyer_body] do
      assert body =~ "workspace-table-row"
      assert body =~ ~s|html[data-theme="dark"] .workspace-table-row:hover|
    end
  end

  test "workspace index table shells clip to rounded corners like buyers", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    _invoice = insert_invoice!(user, company, %{status: "draft", number: nil})
    _contract = create_contract!(company, %{"status" => "draft", "number" => "C-ROUNDED-1"})

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Rounded Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, _act} = create_act_for_overview(user, company, buyer, "draft")

    invoice_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices")
      |> html_response(200)

    contract_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts")
      |> html_response(200)

    act_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts")
      |> html_response(200)

    buyer_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/buyers")
      |> html_response(200)

    clipped_shell = "overflow-hidden rounded-3xl border border-stone-200 bg-white shadow-sm"

    assert buyer_body =~ clipped_shell
    assert invoice_body =~ clipped_shell
    assert contract_body =~ clipped_shell
    assert act_body =~ clipped_shell
  end

  test "invoice new uses workspace form chrome and keeps invoices nav active", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    create_company_bank_account!(company)

    {:ok, _buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Acme Buyer",
        "bin_iin" => "060215385673",
        "address" => "Buyer Address"
      })

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/new?invoice_type=direct")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/invoices"[^>]*aria-current="page"/
    assert body =~ "Обзор"
    assert body =~ "Режим счета"
    assert body =~ ~s(id="invoice-mode-overview")
    assert body =~ ~s(id="invoice-buyer-overview")
    assert body =~ ~s(id="invoice-bank-account-overview")
    assert body =~ "Прямой (без договора)"
    assert body =~ "const invoiceModeLabels = {"
    assert body =~ ~s(contract: "Из договора")
    assert body =~ "direct: \"Прямой (без договора)\""
    assert body =~ "updateInvoiceModeOverview();"
    assert body =~ "function updateBuyerOverview() {"
    assert body =~ "function updateBankAccountOverview() {"
    assert body =~ ~s(data-overview-name=)
    assert body =~ ~s(data-overview-value=)
    assert body =~ "updateBuyerOverview();"
    assert body =~ "updateBankAccountOverview();"
    assert body =~ "Реквизиты покупателя и оплаты"
    refute body =~ ~s(<div class="bg-white shadow rounded-lg">)
  end

  test "invoice edit uses workspace form chrome and keeps invoices nav active", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    invoice = create_invoice_with_items!(user, company)

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/#{invoice.id}/edit")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/invoices"[^>]*aria-current="page"/
    assert body =~ "Обзор"
    assert body =~ "Статус"
    assert body =~ "Реквизиты покупателя и оплаты"
    refute body =~ ~s(<div class="bg-white shadow rounded-lg">)
  end

  test "invoice show uses workspace detail chrome and keeps invoices nav active", %{
    conn: conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    invoice = create_invoice_with_items!(user, company)

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/#{invoice.id}")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/invoices"[^>]*aria-current="page"/
    assert body =~ "Обзор"
    assert body =~ "Статус"
    assert body =~ "Просмотр документа"
    assert body =~ ~r/<h1[^>]*class="[^"]*text-2xl[^"]*"/
    refute body =~ ~r/<h1[^>]*class="[^"]*text-3xl[^"]*"/
    refute body =~ ~s(<div class="nav-bar">)
  end

  test "invoice show hides issue and paid actions when the linked contract is not signed", %{
    conn: conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    create_company_bank_account!(company)

    unsigned_contract = create_contract!(company, %{"status" => "issued"})

    draft_invoice =
      create_invoice_with_items!(user, company, %{
        "contract_id" => unsigned_contract.id
      })

    issued_invoice =
      insert_invoice!(user, company, %{
        status: "issued",
        contract_id: unsigned_contract.id,
        number: "00000000999"
      })

    draft_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/#{draft_invoice.id}")
      |> html_response(200)

    issued_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/#{issued_invoice.id}")
      |> html_response(200)

    refute draft_body =~ ">Issue<"
    refute issued_body =~ "Mark as Paid"
  end

  test "invoice show renders send menu as a fixed overlay below the trigger", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    invoice = insert_invoice!(user, company, %{status: "issued", number: "INV-2026-2"})

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/#{invoice.id}")
      |> html_response(200)

    assert body =~ "data-send-menu-root"
    assert body =~ "data-send-menu-panel"
    assert body =~ "fixed left-0 top-0 z-[80] hidden"
    assert body =~ ~s(ontoggle="window.positionWorkspaceSendMenu)
    assert body =~ "triggerRect.bottom + gap"
    assert body =~ "positionWorkspaceOverlay(detailsEl, '[data-send-menu-panel]', 'below');"
  end

  test "contract new uses workspace form chrome and keeps contracts nav active", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    create_company_bank_account!(company)

    {:ok, _buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Contract Buyer",
        "bin_iin" => "060215385673"
      })

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts/new")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/contracts"[^>]*aria-current="page"/
    assert body =~ "Обзор"
    assert body =~ "Данные договора"
    refute body =~ ~s(<div class="bg-white shadow sm:rounded-lg">)
  end

  test "act new uses workspace form chrome and keeps acts nav active", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, _buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/new?act_type=direct")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/acts"[^>]*aria-current="page"/
    assert body =~ "Обзор"
    assert body =~ "Тип акта"
    refute body =~ ~s(<div class="bg-white shadow sm:rounded-lg">)
  end

  test "invoice and act new include explicit dark-theme fallback hooks for mode toggles and items areas",
       %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    create_company_bank_account!(company)

    {:ok, _buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Dark Contrast Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    _signed_contract =
      create_contract!(company, %{"status" => "signed", "number" => "C-DARK-MODE-1"})

    invoice_direct_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/new?invoice_type=direct")
      |> html_response(200)

    invoice_contract_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/new?invoice_type=contract")
      |> html_response(200)

    act_direct_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/new?act_type=direct")
      |> html_response(200)

    act_contract_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/new?act_type=contract")
      |> html_response(200)

    for body <- [invoice_direct_body, invoice_contract_body, act_direct_body, act_contract_body] do
      assert body =~ "workspace-form-mode-surface"
      assert body =~ "workspace-form-mode-option"
      assert body =~ "workspace-form-items-surface"
      assert body =~ "workspace-form-items-heading"
      assert body =~ "workspace-form-item-label"
      assert body =~ "dark:border-slate-600 dark:bg-slate-800/80"
      assert body =~ "text-sm font-medium text-slate-700 dark:text-slate-100"
      assert body =~ "rounded-2xl bg-slate-50 p-4 dark:bg-slate-900/80"
      assert body =~ "text-lg font-semibold text-slate-900 dark:text-slate-100"
      assert body =~ ~s|html[data-theme="dark"] .workspace-form-mode-surface|
      assert body =~ ~s|html[data-theme="dark"] .workspace-form-mode-option|
      assert body =~ ~s|html[data-theme="dark"] .workspace-form-items-surface|
      assert body =~ ~s|html[data-theme="dark"] .workspace-form-items-heading|
      assert body =~ ~s|html[data-theme="dark"] .workspace-form-item-label|
    end

    assert invoice_direct_body =~
             ~s(<form action="/invoices" method="post" class="workspace-form space-y-6">)

    for body <- [invoice_direct_body, invoice_contract_body, act_direct_body, act_contract_body] do
      assert body =~ "text-gray-500 dark:text-slate-300"
      assert body =~ "text-gray-900 dark:text-slate-100"
      assert body =~ "dark:bg-slate-800"
      assert body =~ "ring-gray-300 dark:ring-slate-600"
    end
  end

  test "contract new includes explicit dark-theme hooks for currency and items surfaces", %{
    conn: conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    create_company_bank_account!(company)

    {:ok, _buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Contract Dark Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts/new")
      |> html_response(200)

    assert body =~ ~s(<form action="/contracts" method="post" class="workspace-form space-y-6">)
    assert body =~ ~r/class="[^"]*workspace-form-static-value[^"]*">[\s]*KZT[\s]*<\/div>/
    assert body =~ ~r/class="[^"]*workspace-form-items-surface[^"]*"/
    assert body =~ ~r/class="[^"]*workspace-form-items-heading[^"]*"/
    assert body =~ ~r/class="[^"]*workspace-form-item-label[^"]*"/
    assert body =~ ~s|html[data-theme="dark"] .workspace-form-static-value|
    assert body =~ ~s|html[data-theme="dark"] .workspace-form-items-surface|
    assert body =~ ~s|html[data-theme="dark"] .workspace-form-items-heading|
    assert body =~ ~s|html[data-theme="dark"] .workspace-form-item-label|
  end

  test "act new syncs buyer address when direct mode buyer changes", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, _buyer_one} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Act Buyer 1",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address 1"
      })

    {:ok, _buyer_two} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Act Buyer 2",
        "bin_iin" => "090215385679",
        "address" => "Buyer Address 2"
      })

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/new?act_type=direct")
      |> html_response(200)

    assert body =~ ~s(name="act[buyer_address]")
    assert body =~ ~s(data-address=)
    assert body =~ "function setBuyerAddress(value) {"
    assert body =~ "document.getElementById('buyer_select')?.addEventListener('change'"
    assert body =~ "setBuyerAddress(option.getAttribute('data-address') || '')"
  end

  test "contract show uses workspace detail chrome and keeps contracts nav active", %{
    conn: conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    contract = create_contract!(company, %{"status" => "draft", "number" => "C-1"})

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts/#{contract.id}")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/contracts"[^>]*aria-current="page"/
    assert body =~ "Обзор"
    assert body =~ "Статус"
    assert body =~ "Просмотр документа"
    refute body =~ ~s(<div class="nav-bar">)
  end

  test "contract show renders send menu as a fixed overlay below the trigger", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    contract = create_contract!(company, %{"status" => "issued", "number" => "C-9"})

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts/#{contract.id}")
      |> html_response(200)

    assert body =~ "data-send-menu-root"
    assert body =~ "data-send-menu-panel"
    assert body =~ "fixed left-0 top-0 z-[80] hidden"
    assert body =~ ~s(ontoggle="window.positionWorkspaceSendMenu)
    assert body =~ "triggerRect.bottom + gap"
    assert body =~ "positionWorkspaceOverlay(detailsEl, '[data-send-menu-panel]', 'below');"
  end

  test "contract edit uses workspace form chrome and keeps contracts nav active", %{
    conn: conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    create_company_bank_account!(company)

    {:ok, _buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Contract Buyer",
        "bin_iin" => "060215385673"
      })

    contract = create_contract!(company, %{"status" => "draft", "number" => "C-2"})

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts/#{contract.id}/edit")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/contracts"[^>]*aria-current="page"/
    assert body =~ "Обзор"
    assert body =~ "Данные договора"
    assert body =~ "Покупатель и банковские реквизиты"
    refute body =~ ~s(<div class="max-w-5xl mx-auto py-6 sm:px-6 lg:px-8">)
  end

  test "act show uses workspace detail chrome and keeps acts nav active", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, act} = create_act_for_overview(user, company, buyer, "draft")

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/#{act.id}")
      |> html_response(200)

    assert body =~ ~r/<a[^>]*href="\/acts"[^>]*aria-current="page"/
    assert body =~ "Обзор"
    assert body =~ "Статус"
    assert body =~ "Просмотр документа"
    assert body =~ ".act-title {"
    assert body =~ "margin-top: 12px;"
    refute body =~ "margin-top: -22px;"
    assert body =~ ~s(width: 6%;)
    assert body =~ ~s(width: 10%;)
    assert body =~ ~s(width: 16%;)
    refute body =~ ~s(width: 4%;)
    refute body =~ ~s(<div class="mb-4 flex items-center justify-between">)
  end

  test "act show renders send menu as a fixed overlay below the trigger", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, act} = create_act_for_overview(user, company, buyer, "issued")

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/#{act.id}")
      |> html_response(200)

    assert body =~ "data-send-menu-root"
    assert body =~ "data-send-menu-panel"
    assert body =~ "fixed left-0 top-0 z-[80] hidden"
    assert body =~ ~s(ontoggle="window.positionWorkspaceSendMenu)
    assert body =~ "triggerRect.bottom + gap"
    assert body =~ "positionWorkspaceOverlay(detailsEl, '[data-send-menu-panel]', 'below');"
  end

  test "workspace_row_actions renders inline and overflow affordances", _context do
    html =
      render_component(&EdocApiWeb.CoreComponents.workspace_row_actions/1,
        primary: %{label: "View", transport: :link, method: :get, href: "/invoices/1"},
        secondary: [
          %{
            label: "Delete",
            transport: :htmx_delete,
            method: :delete,
            hx_delete: "/invoices/1",
            row_dom_id: "invoice-1",
            confirm_text: "Delete this invoice?"
          }
        ],
        mobile_mode: :overflow,
        row_id: "invoice-1"
      )

    assert html =~ ~r/<a[^>]*href="\/invoices\/1"[^>]*>\s*View\s*<\/a>/s
    assert html =~ ~r/<summary[^>]*>\s*Actions\s*<\/summary>/s
    assert html =~ ~s(data-row-actions-menu)
    assert html =~ ~s(fixed left-0 top-0 z-[80])
    assert html =~ ~s(ontoggle="window.positionWorkspaceRowActions)
    assert html =~ ~r/hx-delete="\/invoices\/1"/
    assert html =~ ~r/hx-target="#invoice-1"/
    assert html =~ ~r/hx-swap="outerHTML"/

    assert html =~
             ~r/hx-on::after-request="if\(event\.detail\.successful\) window\.location\.reload\(\)"/

    assert html =~ ~r/<details[^>]*>/
  end

  test "workspace_row_actions form transport escapes confirm text and keeps phase-1 post semantics",
       _context do
    html =
      render_component(&EdocApiWeb.CoreComponents.workspace_row_actions/1,
        primary: %{
          label: "Paid",
          transport: :form,
          method: :post,
          action: "/invoices/1/pay",
          confirm_text: "Mark invoice as paid? It's final."
        },
        secondary: [],
        mobile_mode: :overflow
      )

    assert html =~ ~s(<form action="/invoices/1/pay" method="post")
    assert html =~ ~s(name="_csrf_token")
    refute html =~ ~s(name="_method")
    refute html =~ ~s|return confirm('Mark invoice as paid? It's final.')|
    assert html =~ ~s|return confirm(&quot;Mark invoice as paid? It&#39;s final.&quot;)|
  end

  test "buyers, contracts, invoices, and acts use the approved semantic submenu text colors",
       %{conn: conn} do
    buyer_actions =
      EdocApiWeb.BuyerHTML.row_actions(%{
        id: Ecto.UUID.generate()
      })

    buyer_menu =
      render_component(&EdocApiWeb.CoreComponents.workspace_row_actions/1,
        primary: buyer_actions.primary,
        secondary: buyer_actions.secondary,
        desktop_mode: :overflow,
        mobile_mode: :overflow
      )

    contract_actions =
      EdocApiWeb.ContractHTML.contract_row_actions(%{
        id: Ecto.UUID.generate(),
        status: "issued"
      })

    contract_menu =
      render_component(&EdocApiWeb.CoreComponents.workspace_row_actions/1,
        primary: contract_actions.primary,
        secondary: contract_actions.secondary,
        desktop_mode: :overflow,
        mobile_mode: :overflow
      )

    invoice_actions =
      EdocApiWeb.InvoicesHTML.row_actions(%{
        id: Ecto.UUID.generate(),
        status: "draft"
      })

    invoice_menu =
      render_component(&EdocApiWeb.CoreComponents.workspace_row_actions/1,
        primary: invoice_actions.primary,
        secondary: invoice_actions.secondary,
        desktop_mode: :overflow,
        mobile_mode: :overflow
      )

    blocked_invoice_actions =
      EdocApiWeb.InvoicesHTML.row_actions(%{
        id: Ecto.UUID.generate(),
        status: "issued",
        contract_id: Ecto.UUID.generate(),
        contract: %{status: "issued"}
      })

    act_actions =
      EdocApiWeb.ActHTML.act_row_actions(%{
        id: Ecto.UUID.generate(),
        status: "draft"
      })

    act_menu =
      render_component(&EdocApiWeb.CoreComponents.workspace_row_actions/1,
        primary: act_actions.primary,
        secondary: act_actions.secondary,
        desktop_mode: :overflow,
        mobile_mode: :overflow
      )

    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    invoice = insert_invoice!(user, company, %{status: "issued", number: "INV-2026-2"})
    contract = create_contract!(company, %{"status" => "issued", "number" => "C-9"})

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, act} = create_act_for_overview(user, company, buyer, "issued")

    invoice_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/#{invoice.id}")
      |> html_response(200)

    contract_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts/#{contract.id}")
      |> html_response(200)

    act_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/#{act.id}")
      |> html_response(200)

    assert buyer_menu =~ "text-sky-700"
    assert buyer_menu =~ "text-emerald-700"
    assert buyer_menu =~ "text-rose-700"

    assert contract_menu =~ "text-sky-700"
    assert contract_menu =~ "text-emerald-700"

    assert invoice_menu =~ "text-sky-700"
    assert invoice_menu =~ "text-rose-700"
    refute Enum.any?(blocked_invoice_actions.secondary, &(&1.label == "Paid"))

    assert act_menu =~ "text-sky-700"
    assert act_menu =~ "text-rose-700"

    assert invoice_body =~
             "send-menu-item block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-slate-700 transition hover:bg-slate-100 hover:text-slate-900"

    assert invoice_body =~
             "send-menu-item block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-emerald-700 transition hover:bg-slate-100 hover:text-emerald-900"

    assert invoice_body =~
             "send-menu-item block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-sky-700 transition hover:bg-slate-100 hover:text-sky-900"

    assert contract_body =~
             "send-menu-item block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-slate-700 transition hover:bg-slate-100 hover:text-slate-900"

    assert contract_body =~
             "send-menu-item block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-emerald-700 transition hover:bg-slate-100 hover:text-emerald-900"

    assert contract_body =~
             "send-menu-item block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-sky-700 transition hover:bg-slate-100 hover:text-sky-900"

    assert act_body =~
             "send-menu-item block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-slate-700 transition hover:bg-slate-100 hover:text-slate-900"

    assert act_body =~
             "send-menu-item block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-emerald-700 transition hover:bg-slate-100 hover:text-emerald-900"

    assert act_body =~
             "send-menu-item block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-sky-700 transition hover:bg-slate-100 hover:text-sky-900"
  end

  test "send submenu items keep action-menu hover treatment while using semantic text colors",
       %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    invoice = insert_invoice!(user, company, %{status: "issued", number: "INV-2026-2"})
    contract = create_contract!(company, %{"status" => "issued", "number" => "C-9"})

    buyer =
      create_buyer_for_acts!(company, %{
        "name" => "Act Buyer",
        "bin_iin" => "080215385677",
        "address" => "Buyer Address"
      })

    {:ok, act} = create_act_for_overview(user, company, buyer, "issued")

    invoice_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/#{invoice.id}")
      |> html_response(200)

    contract_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/contracts/#{contract.id}")
      |> html_response(200)

    act_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/acts/#{act.id}")
      |> html_response(200)

    assert invoice_body =~ "hover:bg-slate-100 hover:text-slate-900"
    assert invoice_body =~ "hover:bg-slate-100 hover:text-emerald-900"
    assert invoice_body =~ "hover:bg-slate-100 hover:text-sky-900"

    assert contract_body =~ "hover:bg-slate-100 hover:text-slate-900"
    assert contract_body =~ "hover:bg-slate-100 hover:text-emerald-900"
    assert contract_body =~ "hover:bg-slate-100 hover:text-sky-900"

    assert act_body =~ "hover:bg-slate-100 hover:text-slate-900"
    assert act_body =~ "hover:bg-slate-100 hover:text-emerald-900"
    assert act_body =~ "hover:bg-slate-100 hover:text-sky-900"

    refute invoice_body =~ ".invoice-doc .send-menu-item:hover {"
    refute contract_body =~ ".contract-doc .send-menu-item:hover"
    refute act_body =~ ".act-doc .send-menu-item:hover"
  end

  test "actions and send submenus include explicit dark-mode contrast classes", %{conn: conn} do
    buyer_actions =
      EdocApiWeb.BuyerHTML.row_actions(%{
        id: Ecto.UUID.generate()
      })

    buyer_menu =
      render_component(&EdocApiWeb.CoreComponents.workspace_row_actions/1,
        primary: buyer_actions.primary,
        secondary: buyer_actions.secondary,
        desktop_mode: :overflow,
        mobile_mode: :overflow
      )

    assert buyer_menu =~ "dark:text-sky-300"
    assert buyer_menu =~ "dark:text-emerald-300"
    assert buyer_menu =~ "dark:text-rose-300"
    assert buyer_menu =~ "dark:hover:bg-slate-700"

    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)
    invoice = insert_invoice!(user, company, %{status: "issued", number: "INV-2026-2"})

    invoice_body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices/#{invoice.id}")
      |> html_response(200)

    assert invoice_body =~ "dark:text-slate-100"
    assert invoice_body =~ "dark:text-emerald-300"
    assert invoice_body =~ "dark:text-sky-300"
    assert invoice_body =~ "dark:hover:bg-slate-700"
  end

  test "layout includes dark-mode overlay submenu contrast hooks", %{conn: conn} do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    create_company!(user)

    body =
      conn
      |> browser_conn(user, "ru")
      |> get("/invoices")
      |> html_response(200)

    assert body =~ ~s|html[data-theme="dark"] [data-row-actions-menu],|
    assert body =~ ~s|html[data-theme="dark"] [data-send-menu-panel] {|
    assert body =~ "background-color: #334155;"
    assert body =~ "border-color: #94a3b8;"
    assert body =~ ~s|html[data-theme="dark"] [data-row-actions-menu] .text-sky-700,|
    assert body =~ ~s|html[data-theme="dark"] [data-send-menu-panel] .text-sky-700 {|
    assert body =~ "color: #7dd3fc;"
  end

  test "workspace_row_actions get forms preserve method semantics without CSRF fields",
       _context do
    html =
      render_component(&EdocApiWeb.CoreComponents.workspace_row_actions/1,
        primary: %{
          label: "Search",
          transport: :form,
          method: :get,
          action: "/invoices"
        },
        secondary: [],
        mobile_mode: :overflow
      )

    assert html =~ ~s(<form action="/invoices" method="get")
    refute html =~ ~s(name="_csrf_token")
    refute html =~ ~s(name="_method")
  end

  test "flash_error keeps shared info and error surfaces by default", _context do
    html =
      render_component(&EdocApiWeb.CoreComponents.flash_error/1,
        flash: %{"info" => "Saved", "error" => "Validation failed"}
      )

    assert html =~ "Saved"
    assert html =~ "Validation failed"
    assert html =~ "bg-emerald-50"
    assert html =~ "bg-rose-50"
  end

  test "flash_error omits the wrapper when only info exists and info rendering is disabled",
       _context do
    html =
      render_component(&EdocApiWeb.CoreComponents.flash_error/1,
        flash: %{"info" => "Saved"},
        include_info: false
      )

    assert html == ""
  end

  test "flash_error can opt out of info surfaces while still showing errors", _context do
    html =
      render_component(&EdocApiWeb.CoreComponents.flash_error/1,
        flash: %{"info" => "Saved", "error" => "Validation failed"},
        include_info: false
      )

    assert html =~ "Validation failed"
    assert html =~ "bg-rose-50"
    refute html =~ "Saved"
    refute html =~ "bg-emerald-50"
  end

  test "invoices and buyers overview pages render the shared flash rhythm explicitly", %{
    conn: _conn
  } do
    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)
    company = create_company!(user)

    {:ok, _buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        "name" => "Acme Buyer",
        "bin_iin" => "060215385673"
      })

    invoice_body =
      build_conn()
      |> browser_conn(user, "en")
      |> fetch_flash()
      |> put_flash(:info, "Saved")
      |> put_flash(:error, "Failed")
      |> get("/invoices")
      |> html_response(200)

    buyers_body =
      build_conn()
      |> browser_conn(user, "en")
      |> fetch_flash()
      |> put_flash(:info, "Saved")
      |> put_flash(:error, "Failed")
      |> get("/buyers")
      |> html_response(200)

    for body <- [invoice_body, buyers_body] do
      assert body =~ "Saved"
      assert body =~ "Failed"
      assert body =~ "bg-emerald-50"
      assert body =~ "bg-rose-50"
      assert length(Regex.scan(~r/>Saved</, body)) == 1
    end
  end

  defp browser_conn(conn, user, locale) do
    conn
    |> Plug.Test.init_test_session(%{user_id: user.id, locale: locale})
    |> put_private(:plug_skip_csrf_protection, true)
    |> put_req_header("accept", "text/html")
  end

  defp create_buyer_for_acts!(company, attrs) do
    {:ok, buyer} = EdocApi.Buyers.create_buyer_for_company(company.id, attrs)
    buyer
  end

  defp create_act_for_overview(user, company, buyer, status) do
    attrs = %{
      "issue_date" => Date.utc_today(),
      "buyer_id" => buyer.id,
      "buyer_address" => "Buyer Address",
      "items" => [
        %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
      ]
    }

    with {:ok, act} <- EdocApi.Acts.create_act_for_user(user.id, company.id, attrs) do
      updated_act =
        act
        |> Ecto.Changeset.change(status: status)
        |> EdocApi.Repo.update!()

      {:ok, updated_act}
    end
  end
end
