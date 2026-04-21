defmodule EdocApiWeb.AdminBillingController do
  use EdocApiWeb, :controller

  alias EdocApi.Billing

  plug(:put_view, html: EdocApiWeb.AdminBillingHTML)

  def index(conn, _params) do
    redirect(conn, to: "/admin/billing/clients")
  end

  def clients(conn, _params) do
    render(conn, :clients,
      clients: Billing.list_admin_clients(),
      dashboard: Billing.admin_billing_dashboard()
    )
  end

  def client(conn, %{"id" => id}) do
    render(conn, :client, client: Billing.get_admin_client!(id))
  end

  def invoices(conn, params) do
    render(conn, :invoices,
      invoices: Billing.list_admin_billing_invoices(params),
      selected_status: params["status"] || ""
    )
  end

  def create_renewal_invoice(conn, %{"id" => subscription_id} = params) do
    plan = params["plan"] || params["plan_code"] || "basic"

    case Billing.create_renewal_invoice(subscription_id, plan) do
      {:ok, invoice} ->
        audit_admin_action(
          conn,
          invoice.company_id,
          "admin_renewal_invoice_created",
          "billing_invoice",
          invoice.id,
          %{
            plan: plan,
            subscription_id: subscription_id
          }
        )

        redirect(conn, to: "/admin/billing/invoices")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not create renewal invoice.")
        |> redirect(to: "/admin/billing/clients")
    end
  end

  def create_upgrade_invoice(conn, %{"id" => subscription_id} = params) do
    plan = params["plan"] || params["plan_code"] || "basic"

    case Billing.create_immediate_upgrade_invoice(subscription_id, plan) do
      {:ok, invoice} ->
        audit_admin_action(
          conn,
          invoice.company_id,
          "admin_upgrade_invoice_created",
          "billing_invoice",
          invoice.id,
          %{
            plan: plan,
            subscription_id: subscription_id
          }
        )

        redirect(conn, to: "/admin/billing/invoices")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not create upgrade invoice.")
        |> redirect(to: "/admin/billing/clients")
    end
  end

  def send_invoice(conn, %{"id" => invoice_id} = params) do
    attrs = Map.get(params, "invoice", params)

    case Billing.attach_kaspi_payment_link(invoice_id, attrs["kaspi_payment_link"]) do
      {:ok, invoice} ->
        {:ok, sent_invoice} =
          Billing.send_billing_invoice(invoice,
            payment_method: invoice.payment_method,
            kaspi_payment_link: invoice.kaspi_payment_link
          )

        audit_admin_action(
          conn,
          sent_invoice.company_id,
          "admin_invoice_sent",
          "billing_invoice",
          sent_invoice.id,
          %{
            payment_method: sent_invoice.payment_method,
            kaspi_payment_link: sent_invoice.kaspi_payment_link
          }
        )

        redirect(conn, to: "/admin/billing/invoices")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not send billing invoice.")
        |> redirect(to: "/admin/billing/invoices")
    end
  end

  def create_payment(conn, %{"id" => invoice_id} = params) do
    attrs = Map.get(params, "payment", params)

    case Billing.create_payment(invoice_id,
           method: attrs["method"] || "manual",
           amount_kzt: parse_integer(attrs["amount_kzt"])
         ) do
      {:ok, payment} ->
        audit_admin_action(
          conn,
          payment.company_id,
          "admin_payment_created",
          "payment",
          payment.id,
          %{
            billing_invoice_id: invoice_id,
            method: payment.method,
            amount_kzt: payment.amount_kzt
          }
        )

        redirect(conn, to: "/admin/billing/invoices")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not create payment.")
        |> redirect(to: "/admin/billing/invoices")
    end
  end

  def confirm_payment(conn, %{"id" => payment_id}) do
    {:ok, result} = Billing.confirm_manual_payment(payment_id, conn.assigns.current_user)

    audit_admin_action(
      conn,
      result.payment.company_id,
      "admin_payment_confirmed",
      "payment",
      result.payment.id,
      %{
        billing_invoice_id: result.invoice.id,
        subscription_id: result.subscription.id
      }
    )

    redirect(conn, to: "/admin/billing/invoices")
  end

  def reject_payment(conn, %{"id" => payment_id}) do
    {:ok, payment} = Billing.reject_payment(payment_id, conn.assigns.current_user)

    audit_admin_action(
      conn,
      payment.company_id,
      "admin_payment_rejected",
      "payment",
      payment.id,
      %{
        billing_invoice_id: payment.billing_invoice_id
      }
    )

    redirect(conn, to: "/admin/billing/invoices")
  end

  def suspend_subscription(conn, %{"id" => subscription_id} = params) do
    reason = params["reason"] || "manual_suspension"
    {:ok, subscription} = Billing.suspend_subscription(subscription_id, reason)

    audit_admin_action(
      conn,
      subscription.company_id,
      "admin_subscription_suspended",
      "subscription",
      subscription.id,
      %{
        reason: reason
      }
    )

    redirect(conn, to: "/admin/billing/clients")
  end

  def reactivate_subscription(conn, %{"id" => subscription_id}) do
    {:ok, subscription} = Billing.reactivate_subscription(subscription_id)

    audit_admin_action(
      conn,
      subscription.company_id,
      "admin_subscription_reactivated",
      "subscription",
      subscription.id
    )

    redirect(conn, to: "/admin/billing/clients")
  end

  def extend_grace_period(conn, %{"id" => subscription_id} = params) do
    grace_until =
      parse_date_end(params["grace_until"]) || DateTime.add(DateTime.utc_now(), 7, :day)

    {:ok, subscription} = Billing.extend_grace_period(subscription_id, grace_until)

    audit_admin_action(
      conn,
      subscription.company_id,
      "admin_grace_period_extended",
      "subscription",
      subscription.id,
      %{
        grace_until: grace_until
      }
    )

    redirect(conn, to: "/admin/billing/clients")
  end

  def schedule_upgrade(conn, %{"id" => subscription_id} = params) do
    plan = params["plan"] || "basic"
    effective_at = parse_date_end(params["effective_at"]) || DateTime.utc_now()
    {:ok, subscription} = Billing.schedule_plan_change(subscription_id, plan, effective_at)

    audit_admin_action(
      conn,
      subscription.company_id,
      "admin_plan_change_scheduled",
      "subscription",
      subscription.id,
      %{
        plan: plan,
        effective_at: effective_at
      }
    )

    redirect(conn, to: "/admin/billing/clients")
  end

  def schedule_plan_change(conn, %{"id" => subscription_id} = params) do
    plan = params["plan"] || "starter"
    effective_at = parse_date_end(params["effective_at"]) || DateTime.utc_now()

    case Billing.schedule_downgrade(subscription_id, plan, effective_at) do
      {:ok, subscription} ->
        audit_admin_action(
          conn,
          subscription.company_id,
          "admin_plan_change_scheduled",
          "subscription",
          subscription.id,
          %{
            plan: plan,
            effective_at: effective_at
          }
        )

        redirect(conn, to: "/admin/billing/clients")

      {:error, _reason, _details} ->
        conn
        |> put_flash(:error, "Could not schedule plan change.")
        |> redirect(to: "/admin/billing/clients")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not schedule plan change.")
        |> redirect(to: "/admin/billing/clients")
    end
  end

  def add_extra_seats(conn, %{"id" => subscription_id} = params) do
    case Billing.change_extra_user_seats(subscription_id, params["count"] || "0") do
      {:ok, subscription} ->
        audit_admin_action(
          conn,
          subscription.company_id,
          "admin_extra_seats_updated",
          "subscription",
          subscription.id,
          %{
            extra_user_seats: subscription.extra_user_seats
          }
        )

        redirect(conn, to: "/admin/billing/clients")

      {:error, _reason, _details} ->
        conn
        |> put_flash(:error, "Could not update extra seats.")
        |> redirect(to: "/admin/billing/clients")
    end
  end

  def add_note(conn, %{"id" => company_id, "note" => note}) do
    {:ok, _event} = Billing.add_internal_note(company_id, conn.assigns.current_user, note)
    redirect(conn, to: "/admin/billing/clients/#{company_id}")
  end

  defp audit_admin_action(conn, company_id, action, subject_type, subject_id, metadata \\ %{}) do
    _ =
      Billing.log_admin_billing_action(
        company_id,
        conn.assigns.current_user,
        action,
        subject_type,
        subject_id,
        metadata
      )

    :ok
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _} -> integer
      :error -> nil
    end
  end

  defp parse_date_end(nil), do: nil

  defp parse_date_end(value) do
    with {:ok, date} <- Date.from_iso8601(value) do
      DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    else
      _ -> nil
    end
  end
end
