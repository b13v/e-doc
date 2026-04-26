defmodule EdocApiWeb.AdminBillingControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import Ecto.Query, warn: false
  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Billing
  alias EdocApi.Billing.{BillingAuditEvent, BillingInvoice, Payment, Subscription}
  alias EdocApi.Monetization
  alias EdocApi.Repo

  setup %{conn: conn} do
    {:ok, _} = Billing.seed_default_plans()

    admin = create_user!(%{"email" => "platform-admin@example.com"})
    member = create_user!(%{"email" => "tenant-user@example.com"})
    Accounts.mark_email_verified!(admin.id)
    Accounts.mark_email_verified!(member.id)

    Repo.update_all(from(u in EdocApi.Accounts.User, where: u.id == ^admin.id),
      set: [is_platform_admin: true]
    )

    admin = Accounts.get_user(admin.id)
    company = create_company!(member, %{"name" => "Backoffice Client"})
    {:ok, subscription} = Billing.create_trial_subscription(company)
    {:ok, subscription} = Billing.activate_subscription(subscription, "basic")
    {:ok, _usage} = Billing.record_document_usage(company, "invoice", Ecto.UUID.generate())
    {:ok, invoice} = Billing.create_renewal_invoice(subscription, "basic")

    {:ok, sent_invoice} =
      Billing.send_billing_invoice(invoice, kaspi_payment_link: "https://pay.test/kaspi")

    {:ok, payment} = Billing.create_payment(sent_invoice, method: "kaspi_link")

    admin_conn = html_conn(conn, admin)
    member_conn = html_conn(conn, member)

    {:ok,
     admin_conn: admin_conn,
     member_conn: member_conn,
     admin: admin,
     member: member,
     company: company,
     subscription: subscription,
     billing_invoice: sent_invoice,
     payment: payment}
  end

  test "non-platform admins are forbidden from the billing backoffice", %{member_conn: conn} do
    conn = get(conn, "/admin/billing/clients")

    assert html_response(conn, 403) =~ "Forbidden"
  end

  test "platform admin sees client list with plan, limits, usage, period, and overdue state", %{
    admin_conn: conn
  } do
    body =
      conn
      |> get("/admin/billing/clients")
      |> html_response(200)

    assert body =~ "ТОО"
    assert body =~ "Backoffice Client"
    assert body =~ "Basic"
    assert body =~ "active"
    assert body =~ "1 / 500"
    assert body =~ "1 / 5"
    assert body =~ "Overdue"
    assert body =~ "Active clients"
    assert body =~ ~s(admin-billing-card-heading)
    assert body =~ "Monthly collected"
    assert body =~ "Invoices due soon"
    assert body =~ "Unpaid invoices"
    assert body =~ ~s(admin-billing-table-heading)
    assert body =~ ~s(html[data-theme="dark"] .admin-billing-card-heading)
    assert body =~ ~s(html[data-theme="dark"] .admin-billing-table-heading)
    assert body =~ "color: #ffffff !important;"
  end

  test "platform admin sees legacy monetization tenants in client list", %{
    admin_conn: conn
  } do
    user = create_user!(%{"email" => "legacy-admin-client@example.com"})
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user, %{"name" => "Legacy Admin Client"})

    {:ok, _subscription} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "period_start" => ~U[2026-01-01 00:00:00Z],
        "period_end" => ~U[2026-01-31 00:00:00Z],
        "skip_trial" => true
      })

    body =
      conn
      |> get("/admin/billing/clients")
      |> html_response(200)

    assert body =~ "Legacy Admin Client"
    assert body =~ "Starter"
    assert body =~ "active"
    assert body =~ "1 / 50"
    assert body =~ "1 / 2"
    assert body =~ "31.01.2026"
  end

  test "platform admin sees legacy monetization tenants without created billing invoices", %{
    admin_conn: conn
  } do
    user = create_user!(%{"email" => "legacy-admin-invoices@example.com"})
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user, %{"name" => "Legacy Admin Invoice Client"})

    {:ok, _subscription} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "basic",
        "period_start" => ~U[2026-01-01 00:00:00Z],
        "period_end" => ~U[2026-01-31 00:00:00Z],
        "skip_trial" => true
      })

    body =
      conn
      |> get("/admin/billing/invoices")
      |> html_response(200)

    assert body =~ "Legacy Admin Invoice Client"
    assert body =~ "pending_invoice"
    assert body =~ "Basic"
    assert body =~ "31.01.2026"
    assert body =~ ~s(href="/admin/billing/clients/#{company.id}")
    assert body =~ "Create from client detail"
  end

  test "platform admin can see create invoice action for legacy pending billing client", %{
    admin_conn: conn
  } do
    user = create_user!(%{"email" => "legacy-action-admin@example.com"})
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user, %{"name" => "Legacy Action Client"})

    {:ok, _subscription} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "basic",
        "period_start" => ~U[2026-04-01 00:00:00Z],
        "period_end" => ~U[2026-05-01 00:00:00Z],
        "skip_trial" => true
      })

    body =
      conn
      |> get("/admin/billing/clients/#{company.id}")
      |> html_response(200)

    assert body =~ "Pending billing invoice"
    assert body =~ ~s(action="/admin/billing/clients/#{company.id}/legacy-invoices")
    assert body =~ "Create billing invoice"
  end

  test "platform admin creates billing invoice from legacy pending client", %{
    admin_conn: conn
  } do
    user = create_user!(%{"email" => "legacy-create-admin@example.com"})
    Accounts.mark_email_verified!(user.id)
    company = create_company!(user, %{"name" => "Legacy Create Client"})

    {:ok, _subscription} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "basic",
        "period_start" => ~U[2026-04-01 00:00:00Z],
        "period_end" => ~U[2026-05-01 00:00:00Z],
        "skip_trial" => true
      })

    conn = post(conn, "/admin/billing/clients/#{company.id}/legacy-invoices")

    assert redirected_to(conn) == "/admin/billing/invoices"

    body =
      conn
      |> recycle()
      |> get("/admin/billing/invoices")
      |> html_response(200)

    assert body =~ "Legacy Create Client"
    refute body =~ "pending-"
    refute body =~ "Create from client detail"
  end

  test "platform admin billing uses admin navigation instead of tenant workspace navigation", %{
    admin_conn: conn
  } do
    body =
      conn
      |> get("/admin/billing/clients")
      |> html_response(200)

    assert body =~ ~s(href="/admin/billing/clients")
    assert body =~ ~s(href="/admin/billing/invoices")
    refute body =~ ~s(href="/invoices")
    refute body =~ ~s(href="/contracts")
    refute body =~ ~s(href="/acts")
    refute body =~ ~s(href="/buyers")
    refute body =~ ~s(href="/company")
  end

  test "platform admin is redirected from /admin/billing to /admin/billing/clients", %{
    admin_conn: conn
  } do
    conn = get(conn, "/admin/billing")

    assert redirected_to(conn) == "/admin/billing/clients"
  end

  test "platform admin is redirected from /admin to /admin/billing/clients", %{
    admin_conn: conn
  } do
    conn = get(conn, "/admin")

    assert redirected_to(conn) == "/admin/billing/clients"
  end

  test "platform admin sees client detail with users, invoices, payments, and notes form", %{
    admin_conn: conn,
    company: company,
    subscription: subscription,
    member: member
  } do
    body =
      conn
      |> get("/admin/billing/clients/#{company.id}")
      |> html_response(200)

    assert body =~ "Backoffice Client"
    assert body =~ member.email
    assert body =~ "Invoice History"
    assert body =~ "Payment History"
    assert body =~ ~s(action="/admin/billing/clients/#{company.id}/notes")
    assert body =~ ~s(action="/admin/billing/subscriptions/#{subscription.id}/renewal-invoices")
    assert body =~ ~s(action="/admin/billing/subscriptions/#{subscription.id}/upgrade-invoices")
    assert body =~ ~s(action="/admin/billing/subscriptions/#{subscription.id}/schedule-change")
    refute body =~ ~s(action="/admin/billing/subscriptions/#{subscription.id}/extra-seats")
    assert body =~ ~s(action="/admin/billing/subscriptions/#{subscription.id}/grace-period")
    assert body =~ ~s(action="/admin/billing/subscriptions/#{subscription.id}/suspend")
    assert body =~ ~s(action="/admin/billing/subscriptions/#{subscription.id}/reactivate")
  end

  test "platform admin sees scheduled downgrade state on client detail", %{
    admin_conn: conn,
    company: company
  } do
    assert {:ok, _subscription} = Billing.schedule_tenant_downgrade(company.id, "starter")

    body =
      conn
      |> get("/admin/billing/clients/#{company.id}")
      |> html_response(200)

    assert body =~ "Scheduled plan change"
    assert body =~ "Starter"
  end

  test "platform admin sees a dedicated submitted payments section for tenant reviews", %{
    admin_conn: conn,
    company: company,
    billing_invoice: invoice
  } do
    {:ok, payment} =
      Billing.create_customer_payment_review_for_company(company.id, invoice.id, %{
        "external_reference" => "KASPI-CHECK-42",
        "proof_attachment_url" => "https://example.com/proof.png",
        "note" => "Paid by tenant"
      })

    body =
      conn
      |> get("/admin/billing/clients/#{company.id}")
      |> html_response(200)

    assert body =~ "Submitted payments"
    assert body =~ payment.id
    assert body =~ "KASPI-CHECK-42"
    assert body =~ "https://example.com/proof.png"
    assert body =~ "Paid by tenant"
  end

  test "platform admin sees an empty submitted payments state when there are no tenant reviews",
       %{
         admin_conn: conn,
         company: company
       } do
    body =
      conn
      |> get("/admin/billing/clients/#{company.id}")
      |> html_response(200)

    assert body =~ "Submitted payments"
    assert body =~ "No submitted payment details yet."
  end

  test "platform admin client detail hides removed users from the users pane", %{
    admin_conn: conn,
    company: company,
    member: member
  } do
    insert_membership(company.id, "visible-invite@example.com")
    insert_membership(company.id, "removed-user@example.com", "removed")

    body =
      conn
      |> get("/admin/billing/clients/#{company.id}")
      |> html_response(200)

    assert body =~ member.email
    assert body =~ "visible-invite@example.com"
    refute body =~ "removed-user@example.com"
  end

  test "platform admin filters billing invoices by status and sees Kaspi link and due date", %{
    admin_conn: conn,
    billing_invoice: invoice
  } do
    body =
      conn
      |> get("/admin/billing/invoices?status=sent")
      |> html_response(200)

    assert body =~ invoice.id
    assert body =~ "https://pay.test/kaspi"
    assert body =~ "sent"
    assert body =~ ~s(action="/admin/billing/invoices/#{invoice.id}/send")
    assert body =~ ~s(action="/admin/billing/invoices/#{invoice.id}/payments")
    assert body =~ ~s(target="_blank")
    assert body =~ "Copy link"
    assert body =~ ~s(admin-billing-invoice-table-heading)
    assert body =~ ~s(admin-billing-invoice-action-cell)
    assert body =~ ~s(html[data-theme="dark"] .admin-billing-invoice-table-heading)
    assert body =~ ~s(html[data-theme="dark"] .admin-billing-invoice-action-cell)
  end

  test "platform admin can attach a Kaspi link and it is stored as kaspi_link method", %{
    admin_conn: conn,
    subscription: subscription
  } do
    {:ok, invoice} = Billing.create_upgrade_invoice(subscription, "basic")

    conn =
      post(conn, "/admin/billing/invoices/#{invoice.id}/send", %{
        "invoice" => %{"kaspi_payment_link" => " https://pay.kaspi.kz/new-link "}
      })

    assert redirected_to(conn) == "/admin/billing/invoices"
    updated = Repo.get!(BillingInvoice, invoice.id)
    assert updated.payment_method == "kaspi_link"
    assert updated.kaspi_payment_link == "https://pay.kaspi.kz/new-link"
  end

  test "platform admin can confirm a payment from UI and activate paid invoice", %{
    admin_conn: conn,
    payment: payment,
    billing_invoice: invoice
  } do
    conn = post(conn, "/admin/billing/payments/#{payment.id}/confirm")

    assert redirected_to(conn) == "/admin/billing/invoices"

    assert Repo.get!(Payment, payment.id).status == "confirmed"
    assert Repo.get!(BillingInvoice, invoice.id).status == "paid"

    assert Repo.get_by!(BillingAuditEvent,
             action: "admin_payment_confirmed",
             subject_type: "payment",
             subject_id: payment.id
           ).actor_user_id == conn.assigns.current_user.id
  end

  test "platform admin subscription actions are audit logged", %{
    admin_conn: conn,
    subscription: subscription
  } do
    conn =
      post(conn, "/admin/billing/subscriptions/#{subscription.id}/suspend", %{
        "reason" => "manual_review"
      })

    assert redirected_to(conn) == "/admin/billing/clients"

    assert Repo.get_by!(BillingAuditEvent,
             action: "admin_subscription_suspended",
             subject_type: "subscription",
             subject_id: subscription.id
           ).metadata["reason"] == "manual_review"
  end

  test "platform admin can suspend and reactivate a tenant subscription", %{
    admin_conn: conn,
    subscription: subscription
  } do
    conn =
      post(conn, "/admin/billing/subscriptions/#{subscription.id}/suspend", %{
        "reason" => "manual_review"
      })

    assert redirected_to(conn) == "/admin/billing/clients"
    assert Repo.get!(Subscription, subscription.id).status == "suspended"

    conn = recycle(conn) |> html_conn(conn.assigns.current_user)
    conn = post(conn, "/admin/billing/subscriptions/#{subscription.id}/reactivate")

    assert redirected_to(conn) == "/admin/billing/clients"
    assert Repo.get!(Subscription, subscription.id).status == "active"
  end

  test "platform admin cannot schedule downgrade when current seats violate target plan", %{
    admin_conn: conn,
    company: company,
    subscription: subscription
  } do
    insert_membership(company.id, "extra-one@example.com")
    insert_membership(company.id, "extra-two@example.com")

    conn =
      post(conn, "/admin/billing/subscriptions/#{subscription.id}/schedule-change", %{
        "plan" => "starter",
        "effective_at" => "2026-06-01"
      })

    assert redirected_to(conn) == "/admin/billing/clients"
    assert Repo.get!(Subscription, subscription.id).next_plan_id == nil
  end

  defp html_conn(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{user_id: user.id})
    |> put_private(:plug_skip_csrf_protection, true)
    |> put_req_header("accept", "text/html")
  end

  defp insert_membership(company_id, email, status \\ "invited") do
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
