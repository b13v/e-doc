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

    assert body =~ "Детали подписки"
    assert body =~ "Basic"
    assert body =~ invoice.id
    assert body =~ "https://pay.kaspi.kz/customer"
    assert body =~ "Открыть ссылку на оплату Kaspi"
    assert body =~ "Инструкция по оплате"
    assert body =~ ~s(action="/company/billing/invoices/#{invoice.id}/payments")
    assert body =~ "Понизить до Starter"
    assert body =~ "Starter начнет действовать со следующего расчетного периода."
  end

  test "tenant billing page renders russian copy when locale is ru", %{
    company: company,
    billing_invoice: invoice
  } do
    body =
      localized_conn(company.user_id, "ru")
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "Детали подписки"
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

    assert body =~ "Жазылым мәліметтері"
    assert body =~ "Ағымдағы тариф"
    assert body =~ "Төленбеген шоттар"
    refute body =~ "Billing"
  end

  test "tenant billing page includes explicit dark theme hooks for summary headings and upgrade card",
       %{
         conn: conn,
         company: company
       } do
    {:ok, subscription} = Billing.get_current_subscription(company.id)
    {:ok, _subscription} = Billing.activate_subscription(subscription, "starter")

    body =
      conn
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "company-billing-summary-heading"
    assert body =~ "company-billing-upgrade-card"
    assert body =~ "company-billing-upgrade-title"
    assert body =~ "company-billing-upgrade-copy"
    assert body =~ "html[data-theme=\"dark\"] .company-billing-summary-heading"
    assert body =~ "html[data-theme=\"dark\"] .company-billing-upgrade-card"
    assert body =~ "html[data-theme=\"dark\"] .company-billing-upgrade-title"
    assert body =~ "html[data-theme=\"dark\"] .company-billing-upgrade-copy"
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

  test "tenant sees visible success feedback after submitting payment details", %{
    conn: conn,
    billing_invoice: invoice
  } do
    body =
      conn
      |> post("/company/billing/invoices/#{invoice.id}/payments", %{
        "payment" => %{
          "external_reference" => "VISIBLE-SUCCESS-1",
          "proof_attachment_url" => "https://example.com/proof.png",
          "note" => "Visible flash check"
        }
      })
      |> recycle()
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "Реквизиты платежа отправлены на проверку."
  end

  test "tenant sees invoice-not-found feedback on billing page", %{conn: conn} do
    body =
      conn
      |> post("/company/billing/invoices/#{Ecto.UUID.generate()}/payments", %{
        "payment" => %{"external_reference" => "MISSING-INVOICE-1"}
      })
      |> recycle()
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "Счет на оплату не найден."
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

  test "upgrade invoice request flash is localized in russian", %{company: company} do
    {:ok, subscription} = Billing.get_current_subscription(company.id)
    {:ok, _subscription} = Billing.activate_subscription(subscription, "starter")

    conn =
      localized_conn(company.user_id, "ru")
      |> post("/company/billing/upgrade-invoices", %{
        "plan" => "basic"
      })

    assert redirected_to(conn) == "/company/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "Счет на повышение тарифа запрошен. Ожидайте ссылку для оплаты от администратора системы."
  end

  test "tenant cannot request a duplicate unpaid upgrade invoice", %{
    conn: conn,
    company: company
  } do
    {:ok, subscription} = Billing.get_current_subscription(company.id)
    {:ok, subscription} = Billing.activate_subscription(subscription, "starter")
    {:ok, _invoice} = Billing.create_upgrade_invoice(subscription, "basic")

    conn =
      post(conn, "/company/billing/upgrade-invoices", %{
        "plan" => "basic"
      })

    assert redirected_to(conn) == "/company/billing"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Неоплаченный счет на повышение тарифа уже существует. Оплатите его или обратитесь к администратору системы."
  end

  test "expired upgrade invoice disappears from tenant billing page and tenant can request again",
       %{
         conn: conn,
         company: company
       } do
    {:ok, subscription} = Billing.get_current_subscription(company.id)
    {:ok, subscription} = Billing.activate_subscription(subscription, "starter")

    {:ok, invoice} =
      Billing.create_upgrade_invoice(subscription, "basic", due_at: ~U[2026-04-20 08:00:00Z])

    {:ok, _sent_invoice} =
      Billing.send_billing_invoice(invoice,
        payment_method: "manual",
        now: ~U[2026-04-20 08:00:00Z]
      )

    assert %{canceled_invoices: [_]} =
             Billing.process_expired_upgrade_invoices(now: ~U[2026-04-28 08:00:00Z])

    body =
      conn
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "Предыдущий счет на повышение тарифа истек. Вы можете запросить новый."
    refute body =~ invoice.id

    conn =
      localized_conn(company.user_id, "ru")
      |> post("/company/billing/upgrade-invoices", %{"plan" => "basic"})

    assert redirected_to(conn) == "/company/billing"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "Счет на повышение тарифа запрошен. Ожидайте ссылку для оплаты от администратора системы."
  end

  test "expired-upgrade feedback is shown only once on tenant billing page", %{
    conn: conn,
    company: company
  } do
    {:ok, subscription} = Billing.get_current_subscription(company.id)
    {:ok, subscription} = Billing.activate_subscription(subscription, "starter")

    {:ok, invoice} =
      Billing.create_upgrade_invoice(subscription, "basic", due_at: ~U[2026-04-20 08:00:00Z])

    {:ok, _sent_invoice} =
      Billing.send_billing_invoice(invoice,
        payment_method: "manual",
        now: ~U[2026-04-20 08:00:00Z]
      )

    assert %{canceled_invoices: [_]} =
             Billing.process_expired_upgrade_invoices(now: ~U[2026-04-28 08:00:00Z])

    first_conn = get(conn, "/company/billing")
    first_body = html_response(first_conn, 200)

    second_body =
      first_conn
      |> recycle()
      |> get("/company/billing")
      |> html_response(200)

    assert first_body =~ "Предыдущий счет на повышение тарифа истек. Вы можете запросить новый."
    refute second_body =~ "Предыдущий счет на повышение тарифа истек. Вы можете запросить новый."
  end

  test "tenant can schedule downgrade to starter from billing page", %{
    conn: conn,
    subscription: subscription
  } do
    conn = post(conn, "/company/billing/downgrades", %{"plan" => "starter"})

    assert redirected_to(conn) == "/company/billing"

    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "Starter начнет действовать со следующего расчетного периода."

    subscription = Repo.get!(Billing.Subscription, subscription.id) |> Repo.preload(:next_plan)
    assert subscription.next_plan.code == "starter"
    assert subscription.change_effective_at == subscription.current_period_end
  end

  test "tenant sees scheduled downgrade state on billing page", %{
    conn: conn,
    subscription: subscription
  } do
    {:ok, _subscription} =
      Billing.schedule_tenant_downgrade(subscription.company_id, "starter")

    body =
      conn
      |> get("/company/billing")
      |> html_response(200)

    assert body =~ "Запланированное изменение тарифа"
    assert body =~ "Starter начнет действовать со следующего расчетного периода."
  end

  test "tenant cannot schedule downgrade when occupied seats exceed starter limit", %{
    conn: conn,
    company: company,
    subscription: subscription
  } do
    create_membership(company.id, "downgrade-blocked-1@example.com")
    create_membership(company.id, "downgrade-blocked-2@example.com")

    conn = post(conn, "/company/billing/downgrades", %{"plan" => "starter"})

    assert redirected_to(conn) == "/company/billing"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Удалите лишних участников команды перед переходом на Starter."

    subscription = Repo.get!(Billing.Subscription, subscription.id)
    assert subscription.next_plan_id == nil
    assert subscription.change_effective_at == nil
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
    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "Тарифті көтеру шоты сұралды. Системе әкімшісінен төлем сілтемесін күтіңіз."
  end

  defp localized_conn(user_id, locale) do
    build_conn()
    |> Plug.Test.init_test_session(%{user_id: user_id, locale: locale})
    |> put_private(:plug_skip_csrf_protection, true)
    |> put_req_header("accept", "text/html")
  end

  defp create_membership(company_id, email, status \\ "invited") do
    %EdocApi.Core.TenantMembership{}
    |> EdocApi.Core.TenantMembership.changeset(%{
      company_id: company_id,
      role: "member",
      status: status,
      invite_email: email
    })
    |> Repo.insert!()
  end
end
