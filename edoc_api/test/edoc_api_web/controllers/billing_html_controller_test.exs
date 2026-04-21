defmodule EdocApiWeb.BillingHTMLControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import Ecto.Query, warn: false
  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Billing
  alias EdocApi.Billing.Payment
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

    assert body =~ "Billing"
    assert body =~ "Basic"
    assert body =~ invoice.id
    assert body =~ "https://pay.kaspi.kz/customer"
    assert body =~ "Open Kaspi payment link"
    assert body =~ "Payment instructions"
    assert body =~ ~s(action="/company/billing/invoices/#{invoice.id}/payments")
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

    assert body =~ "Billing access is restricted"
    assert body =~ "payment_overdue"
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
end
