defmodule EdocApiWeb.BillingHTMLControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import Ecto.Query, warn: false
  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Billing
  alias EdocApi.Billing.{BillingInvoice, Payment}
  alias EdocApi.Monetization
  alias EdocApi.Repo

  setup %{conn: conn} do
    {:ok, _} = Billing.seed_default_plans()

    user = create_user!(%{"email" => "tenant-billing@example.com"})
    Accounts.mark_email_verified!(user.id)

    company = create_company!(user, %{"name" => "Tenant Billing Client"})
    {:ok, subscription} = Billing.create_trial_subscription(company)
    {:ok, subscription} = Billing.activate_subscription(subscription, "basic")
    {:ok, invoice} = Billing.create_renewal_invoice(subscription, "basic")
    {:ok, invoice} = Billing.attach_kaspi_payment_link(invoice, "https://pay.kaspi.kz/customer")

    {:ok, invoice} =
      Billing.send_billing_invoice(invoice,
        payment_method: invoice.payment_method,
        kaspi_payment_link: invoice.kaspi_payment_link
      )

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put_private(:plug_skip_csrf_protection, true)
      |> put_req_header("accept", "text/html")

    {:ok, conn: conn, company: company, subscription: subscription, billing_invoice: invoice}
  end

  test "tenant sees current plan, renewal date, outstanding invoice, Kaspi link, and instructions",
       %{
         conn: conn,
         billing_invoice: invoice
       } do
    body =
      conn
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "Оплата"
    assert body =~ "Basic"
    assert body =~ invoice.id
    assert body =~ "https://pay.kaspi.kz/customer"
    assert body =~ "Открыть ссылку на оплату Kaspi"
    assert body =~ "Инструкция по оплате"
    assert body =~ ~s(action="/company/billing/invoices/#{invoice.id}/payments")
  end

  test "tenant billing page renders russian copy when locale is ru", %{
    company: company,
    billing_invoice: invoice
  } do
    body =
      localized_conn(company.user_id, "ru")
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "Оплата"
    assert body =~ "Текущий тариф"
    assert body =~ "Неоплаченные счета"
    assert body =~ "Инструкция по оплате"
    refute body =~ "Billing"
    refute body =~ "Outstanding invoices"
    assert body =~ invoice.id
  end

  test "tenant billing page renders kazakh copy when locale is kk", %{
    company: company
  } do
    body =
      localized_conn(company.user_id, "kk")
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "Төлем"
    assert body =~ "Ағымдағы тариф"
    assert body =~ "Төленбеген шоттар"
    refute body =~ "Billing"
  end

  test "tenant billing page uses stronger dark mode contrast classes", %{
    conn: conn,
    company: company
  } do
    {:ok, subscription} = Billing.get_current_subscription(company.id)
    {:ok, _subscription} = Billing.activate_subscription(subscription, "starter")

    body =
      conn
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "dark:text-slate-200"
    assert body =~ "dark:bg-sky-900/40"
    refute body =~ "dark:text-slate-400"
    refute body =~ "dark:bg-blue-950"
  end

  test "tenant sees legacy monetization plan details when no new billing subscription exists" do
    user = create_user!(%{"email" => "legacy-tenant-billing@example.com"})
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user, %{"name" => "Legacy Tenant Billing Client"})

    {:ok, _legacy_subscription} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "period_start" => ~U[2026-01-01 00:00:00Z],
        "period_end" => ~U[2026-01-31 00:00:00Z],
        "skip_trial" => true
      })

    body =
      build_conn()
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put_private(:plug_skip_csrf_protection, true)
      |> put_req_header("accept", "text/html")
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "Starter"
    assert body =~ "31.01.2026"
    assert body =~ "Нет неоплаченных счетов на оплату."
    refute body =~ "No plan"
  end

  test "tenant sees blocked banner for suspended subscriptions", %{
    conn: conn,
    subscription: subscription
  } do
    {:ok, _subscription} = Billing.suspend_subscription(subscription, "payment_overdue")

    body =
      conn
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "Доступ к оплате ограничен"
    assert body =~ "просрочка оплаты"
  end

  test "tenant can submit payment reference and proof for admin review", %{
    conn: conn,
    billing_invoice: invoice
  } do
    conn =
      post(conn, "/company/billing/invoices/#{invoice.id}/payments", %{
        "payment" => %{
          "external_reference" => "KASPI-CHECK-1",
          "proof_attachment_url" => "https://example.com/proof.png",
          "note" => "Paid by Kaspi transfer"
        }
      })

    assert redirected_to(conn) == "/company/billing"

    payment = Repo.one!(from(p in Payment, where: p.billing_invoice_id == ^invoice.id))
    assert payment.status == "pending_confirmation"
    assert payment.method == "kaspi_link"
    assert payment.external_reference == "KASPI-CHECK-1"
    assert payment.proof_attachment_url == "https://example.com/proof.png"

    assert [note] = Billing.list_payment_review_notes(payment.id)
    assert note.metadata["note"] == "Paid by Kaspi transfer"
  end

  test "payment submission flash is localized in russian", %{
    company: company,
    billing_invoice: invoice
  } do
    conn =
      localized_conn(company.user_id, "ru")
      |> post("/company/billing/invoices/#{invoice.id}/payments", %{
        "payment" => %{
          "external_reference" => "RU-REF-1",
          "proof_attachment_url" => "https://example.com/proof.png",
          "note" => "Оплачено"
        }
      })

    assert redirected_to(conn) == "/company/billing"

    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "Реквизиты платежа отправлены на проверку."
  end

  test "tenant can request an upgrade invoice from the billing page", %{
    conn: conn,
    company: company
  } do
    {:ok, subscription} = Billing.get_current_subscription(company.id)
    {:ok, _subscription} = Billing.activate_subscription(subscription, "starter")

    conn =
      post(conn, "/company/billing/upgrade-invoices", %{
        "plan" => "basic"
      })

    assert redirected_to(conn) == "/company/billing"

    invoice =
      Repo.get_by!(BillingInvoice,
        company_id: company.id,
        note: "upgrade",
        plan_snapshot_code: "basic"
      )

    assert invoice.status == "draft"
  end

  test "upgrade invoice request flash is localized in kazakh", %{
    company: company
  } do
    {:ok, subscription} = Billing.get_current_subscription(company.id)
    {:ok, _subscription} = Billing.activate_subscription(subscription, "starter")

    conn =
      localized_conn(company.user_id, "kk")
      |> post("/company/billing/upgrade-invoices", %{
        "plan" => "basic"
      })

    assert redirected_to(conn) == "/company/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Тарифті көтеру шоты жасалды."
  end

  defp localized_conn(user_id, locale) do
    build_conn()
    |> Plug.Test.init_test_session(%{user_id: user_id, locale: locale})
    |> put_private(:plug_skip_csrf_protection, true)
    |> put_req_header("accept", "text/html")
  end
end
