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
    assert body =~ "xl:grid-cols-[minmax(0,1fr)_18rem]"
    assert body =~ ~r/<td[^>]*>\s*-\s*<\/td>/
    assert body =~ "Обзор"
    assert body =~ "Черновики"
    assert body =~ ">1<"
    assert body =~ "Выставленные счета"
    assert body =~ "Оплаченные счета"
    assert body =~ "Счета зависят от готовых данных компании и покупателя."
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

  test "workspace_row_actions get forms preserve method semantics without CSRF fields", _context do
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

  test "flash_error omits the wrapper when only info exists and info rendering is disabled", _context do
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
end
