defmodule EdocApiWeb.AdminBillingController do
  use EdocApiWeb, :controller

  alias EdocApi.Billing

  plug(:put_view, html: EdocApiWeb.AdminBillingHTML)

  def clients(conn, _params) do
    render(conn, :clients, clients: Billing.list_admin_clients())
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
      {:ok, _invoice} ->
        redirect(conn, to: "/admin/billing/invoices")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not create renewal invoice.")
        |> redirect(to: "/admin/billing/clients")
    end
  end

  def create_upgrade_invoice(conn, %{"id" => subscription_id} = params) do
    plan = params["plan"] || params["plan_code"] || "basic"

    case Billing.create_upgrade_invoice(subscription_id, plan) do
      {:ok, _invoice} ->
        redirect(conn, to: "/admin/billing/invoices")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not create upgrade invoice.")
        |> redirect(to: "/admin/billing/clients")
    end
  end

  def send_invoice(conn, %{"id" => invoice_id} = params) do
    attrs = Map.get(params, "invoice", params)

    case Billing.attach_kaspi_payment_link(invoice_id, attrs["kaspi_payment_link"]) do
      {:ok, invoice} ->
        Billing.send_billing_invoice(invoice,
          payment_method: invoice.payment_method,
          kaspi_payment_link: invoice.kaspi_payment_link
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
      {:ok, _payment} ->
        redirect(conn, to: "/admin/billing/invoices")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not create payment.")
        |> redirect(to: "/admin/billing/invoices")
    end
  end

  def confirm_payment(conn, %{"id" => payment_id}) do
    {:ok, _result} = Billing.confirm_manual_payment(payment_id, conn.assigns.current_user)
    redirect(conn, to: "/admin/billing/invoices")
  end

  def reject_payment(conn, %{"id" => payment_id}) do
    {:ok, _payment} = Billing.reject_payment(payment_id, conn.assigns.current_user)
    redirect(conn, to: "/admin/billing/invoices")
  end

  def suspend_subscription(conn, %{"id" => subscription_id} = params) do
    reason = params["reason"] || "manual_suspension"
    {:ok, _subscription} = Billing.suspend_subscription(subscription_id, reason)
    redirect(conn, to: "/admin/billing/clients")
  end

  def reactivate_subscription(conn, %{"id" => subscription_id}) do
    {:ok, _subscription} = Billing.reactivate_subscription(subscription_id)
    redirect(conn, to: "/admin/billing/clients")
  end

  def extend_grace_period(conn, %{"id" => subscription_id} = params) do
    grace_until =
      parse_date_end(params["grace_until"]) || DateTime.add(DateTime.utc_now(), 7, :day)

    {:ok, _subscription} = Billing.extend_grace_period(subscription_id, grace_until)
    redirect(conn, to: "/admin/billing/clients")
  end

  def schedule_upgrade(conn, %{"id" => subscription_id} = params) do
    plan = params["plan"] || "basic"
    effective_at = parse_date_end(params["effective_at"]) || DateTime.utc_now()
    {:ok, _subscription} = Billing.schedule_plan_change(subscription_id, plan, effective_at)
    redirect(conn, to: "/admin/billing/clients")
  end

  def add_extra_seats(conn, %{"id" => subscription_id} = params) do
    {:ok, _subscription} = Billing.add_extra_user_seats(subscription_id, params["count"] || "1")
    redirect(conn, to: "/admin/billing/clients")
  end

  def add_note(conn, %{"id" => company_id, "note" => note}) do
    {:ok, _event} = Billing.add_internal_note(company_id, conn.assigns.current_user, note)
    redirect(conn, to: "/admin/billing/clients/#{company_id}")
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
