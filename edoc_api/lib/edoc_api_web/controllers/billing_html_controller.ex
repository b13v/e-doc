defmodule EdocApiWeb.BillingHTMLController do
  use EdocApiWeb, :controller

  alias EdocApi.Billing
  alias EdocApi.Companies
  alias EdocApi.Monetization

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
          can_manage_billing: Monetization.can_manage_billing_and_team?(company.id, user.id),
          current_section: :company,
          page_title: gettext("Subscription details")
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
      |> put_flash(:info, gettext("Payment reference was sent for review."))
      |> redirect(to: "/company/billing")
    else
      nil ->
        redirect(conn, to: "/company/setup")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, gettext("Billing invoice not found."))
        |> redirect(to: "/company/billing")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, gettext("Could not send payment reference."))
        |> redirect(to: "/company/billing")
    end
  end

  def create_upgrade_invoice(conn, params) do
    user = conn.assigns.current_user
    plan = params["plan"] || params["plan_code"] || "basic"

    with company when not is_nil(company) <- Companies.get_company_by_user_id(user.id),
         {:ok, _invoice} <- Billing.create_upgrade_invoice_for_company(company.id, plan) do
      conn
      |> put_flash(:info, gettext("Upgrade invoice request was created."))
      |> redirect(to: "/company/billing")
    else
      nil ->
        redirect(conn, to: "/company/setup")

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Could not create upgrade invoice request."))
        |> redirect(to: "/company/billing")
    end
  end

  def create_downgrade(conn, params) do
    user = conn.assigns.current_user
    plan = params["plan"] || params["plan_code"] || "starter"

    with company when not is_nil(company) <- Companies.get_company_by_user_id(user.id),
         true <- Monetization.can_manage_billing_and_team?(company.id, user.id),
         {:ok, _subscription} <- Billing.schedule_tenant_downgrade(company.id, plan) do
      conn
      |> put_flash(:info, gettext("Starter begins from the next billing cycle."))
      |> redirect(to: "/company/billing")
    else
      nil ->
        redirect(conn, to: "/company/setup")

      false ->
        conn
        |> put_flash(
          :error,
          gettext("Only the owner or an admin can manage the tariff and team members.")
        )
        |> redirect(to: "/company/billing")

      {:error, :seat_limit_exceeded_on_downgrade, _details} ->
        conn
        |> put_flash(:error, gettext("Remove extra team members before switching to Starter."))
        |> redirect(to: "/company/billing")

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Could not schedule downgrade."))
        |> redirect(to: "/company/billing")
    end
  end
end
