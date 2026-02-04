defmodule EdocApiWeb.InvoicesController do
  use EdocApiWeb, :controller
  import Ecto.Query, warn: false

  alias EdocApi.Invoicing
  alias EdocApi.InvoiceStatus
  alias EdocApi.Documents.InvoicePdf
  alias EdocApiWeb.UnifiedErrorHandler
  alias EdocApi.Companies
  alias EdocApi.Buyers
  alias EdocApi.Payments
  alias EdocApi.Core
  alias EdocApi.Core.Contract

  defp current_user(conn), do: conn.assigns.current_user

  def index(conn, _params) do
    user = current_user(conn)
    invoices = Invoicing.list_invoices_for_user(user.id)
    render(conn, :index, invoices: invoices, page_title: "Invoices")
  end

  def show(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Invoice not found")
        |> redirect(to: "/invoices")

      invoice ->
        render(conn, :show, invoice: invoice, page_title: "Invoice #{invoice.number}")
    end
  end

  def new(conn, _params) do
    user = current_user(conn)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company/setup")

      company ->
        contracts = get_available_contracts(company.id)
        buyers = Buyers.list_buyers_for_company(company.id)
        bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)

        cond do
          Enum.empty?(buyers) ->
            conn
            |> put_flash(:error, "Please create at least one buyer first")
            |> redirect(to: "/buyers/new")

          Enum.empty?(bank_accounts) ->
            conn
            |> put_flash(:error, "Please add at least one bank account first")
            |> redirect(to: "/company")

          true ->
            render(conn, :new,
              page_title: "New Invoice",
              contracts: contracts,
              buyers: buyers,
              bank_accounts: bank_accounts,
              selected_contract_id: nil,
              selected_buyer_id: nil,
              prefill_items: []
            )
        end
    end
  end

  def create(conn, %{"invoice" => invoice_params, "items" => items_params}) do
    user = current_user(conn)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company")

      company ->
        processed_items = process_items(items_params)
        invoice_params_final = prepare_invoice_params(invoice_params, processed_items, user)

        case Invoicing.create_invoice_for_user(user.id, company.id, invoice_params_final) do
          {:ok, invoice} ->
            conn
            |> put_flash(:info, "Invoice created successfully")
            |> redirect(to: "/invoices/#{invoice.id}")

          {:error, %Ecto.Changeset{} = changeset} ->
            render_with_data(
              conn,
              user,
              company,
              invoice_params,
              "Failed to create invoice: #{format_changeset_errors(changeset)}"
            )

          {:error, :validation, %{changeset: changeset}} ->
            render_with_data(
              conn,
              user,
              company,
              invoice_params,
              "Failed to create invoice: #{format_changeset_errors(changeset)}"
            )

          {:error, reason} ->
            render_with_data(
              conn,
              user,
              company,
              invoice_params,
              "Failed to create invoice: #{reason}"
            )
        end
    end
  end

  def create(conn, %{"invoice" => _invoice_params}) do
    user = current_user(conn)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company")

      company ->
        render_with_data(conn, user, company, %{}, "At least one item is required")
    end
  end

  def create_from_contract(conn, %{"contract_id" => contract_id}) do
    user = current_user(conn)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company")

      company ->
        case Core.get_contract_for_user(user.id, contract_id) do
          {:ok, contract} ->
            contract = EdocApi.Repo.preload(contract, [:buyer, :contract_items])
            contracts = get_available_contracts(company.id)
            buyers = Buyers.list_buyers_for_company(company.id)
            bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)

            prefill_items =
              Enum.map(contract.contract_items || [], fn item ->
                %{
                  "name" => item.name,
                  "code" => item.code,
                  "qty" => to_string(item.qty || 1),
                  "unit_price" => Decimal.to_string(item.unit_price || Decimal.new(0))
                }
              end)

            buyer_id = if contract.buyer, do: contract.buyer.id, else: nil

            render(conn, :new,
              page_title: "New Invoice from Contract #{contract.number}",
              contracts: contracts,
              buyers: buyers,
              bank_accounts: bank_accounts,
              selected_contract_id: contract.id,
              selected_buyer_id: buyer_id,
              prefill_items: prefill_items
            )

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Contract not found")
            |> redirect(to: "/contracts")

          {:error, :company_required} ->
            conn
            |> put_flash(:error, "Please set up your company first")
            |> redirect(to: "/company/setup")
        end
    end
  end

  defp get_available_contracts(company_id) do
    Contract
    |> where([c], c.company_id == ^company_id)
    |> where([c], c.status in ["issued", "signed"])
    |> order_by([c], desc: c.inserted_at)
    |> EdocApi.Repo.all()
    |> EdocApi.Repo.preload([:buyer])
  end

  defp process_items(items_params) do
    items_params
    |> Enum.reject(fn item -> item["name"] == "" or item["name"] == nil end)
    |> Enum.map(fn item ->
      qty = String.to_integer(item["qty"] || "1")
      unit_price = Decimal.new(item["unit_price"] || "0")
      amount = Decimal.mult(unit_price, qty)
      Map.merge(item, %{"qty" => qty, "unit_price" => unit_price, "amount" => amount})
    end)
  end

  defp prepare_invoice_params(invoice_params, processed_items, user) do
    invoice_params
    |> Map.delete("items")
    |> Map.put("items", processed_items)
    |> copy_buyer_from_contract_or_selection(user)
  end

  defp copy_buyer_from_contract_or_selection(invoice_params, user) do
    buyer_id = invoice_params["buyer_id"]
    contract_id = invoice_params["contract_id"]

    cond do
      contract_id && contract_id != "" ->
        case Core.get_contract_for_user(user.id, contract_id) do
          {:ok, contract} when contract.buyer != nil ->
            put_buyer_fields(invoice_params, contract.buyer)

          _ ->
            invoice_params
        end

      buyer_id && buyer_id != "" ->
        case Buyers.get_buyer(buyer_id) do
          nil -> invoice_params
          buyer -> put_buyer_fields(invoice_params, buyer)
        end

      true ->
        invoice_params
    end
  end

  defp put_buyer_fields(params, buyer) do
    params
    |> Map.put("buyer_name", buyer.name)
    |> Map.put("buyer_bin_iin", buyer.bin_iin)
    |> Map.put("buyer_address", buyer.address || "")
    |> Map.put("buyer_company_id", buyer.id)
  end

  defp render_with_data(conn, user, company, invoice_params, error_message) do
    contracts = get_available_contracts(company.id)
    buyers = Buyers.list_buyers_for_company(company.id)
    bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)

    conn
    |> put_flash(:error, error_message)
    |> render(:new,
      page_title: "New Invoice",
      contracts: contracts,
      buyers: buyers,
      bank_accounts: bank_accounts,
      selected_contract_id: invoice_params["contract_id"],
      selected_buyer_id: invoice_params["buyer_id"],
      prefill_items: []
    )
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  def pdf(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Invoice not found")
        |> redirect(to: "/invoices")

      invoice ->
        case InvoicePdf.render(invoice) do
          {:ok, pdf_binary} ->
            conn
            |> put_layout(false)
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="invoice-#{invoice.number}.pdf")
            )
            |> send_resp(200, pdf_binary)

          {:error, _reason} ->
            conn
            |> put_status(:internal_server_error)
            |> put_flash(:error, "Failed to generate PDF")
            |> redirect(to: "/invoices/#{id}")
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = current_user(conn)
    result = Invoicing.delete_invoice_for_user(user.id, id)

    UnifiedErrorHandler.handle_result(conn, result,
      success: fn conn, _data ->
        if UnifiedErrorHandler.htmx_request?(conn) do
          send_resp(conn, :no_content, "")
        else
          conn
          |> put_flash(:info, "Invoice deleted successfully")
          |> redirect(to: "/invoices")
        end
      end,
      error: fn conn, type, details ->
        cond do
          type == :business_rule && details[:rule] == :cannot_delete_issued_invoice ->
            if UnifiedErrorHandler.htmx_request?(conn) do
              conn
              |> put_resp_content_type("text/html")
              |> send_resp(403, "<span class='text-red-600'>Cannot delete issued invoice</span>")
            else
              conn
              |> put_flash(:error, "Cannot delete issued invoice")
              |> redirect(to: "/invoices")
            end

          true ->
            if UnifiedErrorHandler.htmx_request?(conn) do
              conn
              |> put_resp_content_type("text/html")
              |> send_resp(404, "<span class='text-red-600'>Error deleting invoice</span>")
            else
              conn |> put_flash(:error, "Error deleting invoice") |> redirect(to: "/invoices")
            end
        end
      end
    )
  end

  def edit(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Invoice not found")
        |> redirect(to: "/invoices")

      invoice ->
        if InvoiceStatus.is_draft?(invoice.status) do
          changeset = Ecto.Changeset.change(invoice)

          render(conn, :edit,
            invoice: invoice,
            changeset: changeset,
            page_title: "Edit Invoice #{invoice.number}"
          )
        else
          conn
          |> put_flash(:error, "Only draft invoices can be edited")
          |> redirect(to: "/invoices/#{id}")
        end
    end
  end

  def update(conn, %{"id" => id, "invoice" => invoice_params}) do
    user = current_user(conn)

    case Invoicing.update_invoice_for_user(user.id, id, invoice_params) do
      {:ok, invoice} ->
        conn
        |> put_flash(:info, "Invoice updated successfully")
        |> redirect(to: "/invoices/#{invoice.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        invoice = Invoicing.get_invoice_for_user(user.id, id)

        conn
        |> put_flash(:error, "Failed to update invoice: #{format_changeset_errors(changeset)}")
        |> render(:edit,
          invoice: invoice,
          changeset: changeset,
          page_title: "Edit Invoice #{invoice.number}"
        )

      {:error, reason} ->
        invoice = Invoicing.get_invoice_for_user(user.id, id)

        conn
        |> put_flash(:error, "Failed to update invoice: #{reason}")
        |> render(:edit,
          invoice: invoice,
          changeset: Ecto.Changeset.change(invoice, invoice_params),
          page_title: "Edit Invoice #{invoice.number}"
        )
    end
  end

  def issue(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.issue_invoice_for_user(user.id, id) do
      {:ok, invoice} ->
        conn
        |> put_flash(:info, "Invoice issued successfully")
        |> redirect(to: "/invoices/#{invoice.id}")

      {:error, {:business_rule, %{rule: :cannot_issue}}} ->
        conn
        |> put_flash(:error, "Only draft invoices can be issued")
        |> redirect(to: "/invoices/#{id}")

      {:error, {:business_rule, %{rule: :already_issued}}} ->
        conn |> put_flash(:error, "Invoice is already issued") |> redirect(to: "/invoices/#{id}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to issue invoice: #{inspect(reason)}")
        |> redirect(to: "/invoices/#{id}")
    end
  end
end
