defmodule EdocApiWeb.BillingHTMLController do
  use EdocApiWeb, :controller

  alias EdocApi.Billing
  alias EdocApi.Companies

  plug(:put_view, html: EdocApiWeb.BillingHTML)

  def show(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        redirect(conn, to: "/company/setup")

      company ->
        render(conn, :show,
          company: company,
          billing: Billing.tenant_billing_snapshot(company),
          current_section: :company,
          page_title: "Billing"
        )
    end
  end

  def create_payment(conn, %{"id" => invoice_id, "payment" => payment_params}) do
    user = conn.assigns.current_user

    with company when not is_nil(company) <- Companies.get_company_by_user_id(user.id),
         {:ok, _payment} <-
           Billing.create_customer_payment_review_for_company(
             company.id,
             invoice_id,
             payment_params
           ) do
      conn
      |> put_flash(:info, "Payment reference was sent for review.")
      |> redirect(to: "/company/billing")
    else
      nil ->
        redirect(conn, to: "/company/setup")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Billing invoice not found.")
        |> redirect(to: "/company/billing")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not send payment reference.")
        |> redirect(to: "/company/billing")
    end
  end
end
