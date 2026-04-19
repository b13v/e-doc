defmodule EdocApiWeb.InvoicesController do
  use EdocApiWeb, :controller
  import Ecto.Query, warn: false

  plug(
    :put_view,
    EdocApiWeb.InvoiceHTML when action in [:new, :create, :create_from_contract, :show]
  )

  alias EdocApi.Invoicing
  alias EdocApi.InvoiceStatus
  alias EdocApi.Documents.PdfRequests
  alias EdocApiWeb.ErrorHelpers
  alias EdocApiWeb.UnifiedErrorHandler
  alias EdocApi.Companies
  alias EdocApi.Buyers
  alias EdocApi.Monetization
  alias EdocApi.Payments

  defp current_user(conn), do: conn.assigns.current_user

  def index(conn, params) do
    user = current_user(conn)
    %{page: page, page_size: page_size, offset: offset} = html_pagination_params(params)
    invoices = Invoicing.list_invoices_for_user(user.id, limit: page_size, offset: offset)
    total_count = Invoicing.count_invoices_for_user(user.id)

    render(conn, :index,
      invoices: invoices,
      invoice_summary: Invoicing.invoice_summary_for_user(user.id),
      overdue_count: Invoicing.count_overdue_invoices_for_user(user.id),
      current_section: :invoices,
      page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages(total_count, page_size),
      page_title: gettext("Invoices")
    )
  end

  def overdue(conn, params) do
    user = current_user(conn)
    %{page: page, page_size: page_size, offset: offset} = html_pagination_params(params)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        subscription = Monetization.subscription_snapshot(company.id)
        basic_plan? = subscription.plan == "basic"

        {invoices, total_count} =
          if basic_plan? do
            {
              Invoicing.list_overdue_invoices_for_user(user.id,
                limit: page_size,
                offset: offset
              ),
              Invoicing.count_overdue_invoices_for_user(user.id)
            }
          else
            {[], 0}
          end

        render(conn, :overdue,
          invoices: invoices,
          overdue_count: total_count,
          basic_plan?: basic_plan?,
          subscription: subscription,
          current_section: :invoices,
          page: page,
          page_size: page_size,
          total_count: total_count,
          total_pages: total_pages(total_count, page_size),
          page_title: gettext("Overdue invoices")
        )
    end
  end

  def show(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, gettext("Invoice not found."))
        |> redirect(to: "/invoices")

      invoice ->
        render(conn, :show,
          invoice: invoice,
          current_section: :invoices,
          page_title: gettext("Invoice %{number}", number: invoice.number)
        )
    end
  end

  def new(conn, params) do
    user = current_user(conn)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        contracts = Invoicing.list_invoice_source_contracts_for_user(user.id)
        buyers = Buyers.list_buyers_for_company(company.id)
        bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)

        cond do
          Enum.empty?(buyers) ->
            conn
            |> put_flash(:error, gettext("Please create at least one buyer first."))
            |> redirect(to: "/buyers/new")

          Enum.empty?(bank_accounts) ->
            conn
            |> put_flash(:error, gettext("Please add at least one bank account first."))
            |> redirect(to: "/company")

          true ->
            contract_id = normalize_selected_contract_id(params["contract_id"])
            prefill = prefill_from_contract(user.id, contract_id)

            selected_bank_account_id =
              prefill.selected_bank_account_id || default_bank_account_id(bank_accounts)

            kbe_codes = Payments.list_kbe_codes()
            knp_codes = Payments.list_knp_codes()

            conn =
              if contract_id && prefill.prefill_items == [] do
                put_flash(conn, :info, gettext("The selected contract has no items to copy."))
              else
                conn
              end

            render(conn, :new,
              page_title: gettext("New Invoice"),
              current_section: :invoices,
              contracts: contracts,
              buyers: buyers,
              bank_accounts: bank_accounts,
              kbe_codes: kbe_codes,
              knp_codes: knp_codes,
              invoice_type: params["invoice_type"] || "contract",
              selected_bank_account_id: selected_bank_account_id,
              selected_kbe_code_id:
                bank_account_kbe_code_id(bank_accounts, selected_bank_account_id) ||
                  first_code_id(kbe_codes),
              selected_knp_code_id:
                bank_account_knp_code_id(bank_accounts, selected_bank_account_id) ||
                  first_code_id(knp_codes),
              selected_contract_id: prefill.selected_contract_id,
              selected_buyer_id: prefill.selected_buyer_id,
              buyer_address: prefill.buyer_address || "",
              prefill_items: prefill.prefill_items
            )
        end
    end
  end

  def create(conn, %{"invoice" => invoice_params, "items" => items_params}) do
    user = current_user(conn)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company")

      company ->
        processed_items = process_items(items_params)
        invoice_params_final = prepare_invoice_params(invoice_params, processed_items, user)

        case validate_selected_contract(user.id, invoice_params_final["contract_id"]) do
          :ok ->
            case Invoicing.create_invoice_for_user(user.id, company.id, invoice_params_final) do
              {:ok, invoice} ->
                conn
                |> put_flash(:info, gettext("Invoice created successfully."))
                |> redirect(to: "/invoices/#{invoice.id}")

              {:error, %Ecto.Changeset{} = changeset} ->
                render_with_data(
                  conn,
                  user,
                  company,
                  invoice_params,
                  gettext("Failed to create invoice: %{details}",
                    details: ErrorHelpers.format_changeset_errors(changeset)
                  )
                )

              {:error, :validation, %{changeset: changeset}} ->
                render_with_data(
                  conn,
                  user,
                  company,
                  invoice_params,
                  gettext("Failed to create invoice: %{details}",
                    details: ErrorHelpers.format_changeset_errors(changeset)
                  )
                )

              {:error, :business_rule, %{rule: :quota_exceeded}} ->
                render_with_data(
                  conn,
                  user,
                  company,
                  invoice_params,
                  gettext(
                    "Document limit reached for this billing period. Upgrade your plan to continue."
                  )
                )

              {:error, reason} ->
                render_with_data(
                  conn,
                  user,
                  company,
                  invoice_params,
                  gettext("Failed to create invoice: %{reason}", reason: inspect(reason))
                )
            end

          {:error, message} ->
            render_with_data(conn, user, company, invoice_params, message)
        end
    end
  end

  def create(conn, %{"invoice" => _invoice_params}) do
    user = current_user(conn)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company")

      company ->
        render_with_data(conn, user, company, %{}, gettext("At least one item is required."))
    end
  end

  def create_from_contract(conn, %{"contract_id" => contract_id}) do
    redirect(conn, to: "/invoices/new?invoice_type=contract&contract_id=#{contract_id}")
  end

  defp html_pagination_params(params) do
    page = params |> Map.get("page", "1") |> parse_positive_int(1)
    page_size = params |> Map.get("page_size", "50") |> parse_positive_int(50) |> min(100)
    offset = (page - 1) * page_size

    %{page: page, page_size: page_size, offset: offset}
  end

  defp parse_positive_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp parse_positive_int(_, default), do: default

  defp total_pages(total_count, page_size) when page_size > 0 do
    max(1, div(total_count + page_size - 1, page_size))
  end

  defp process_items(items_params) do
    items_params
    |> normalize_items_params()
    |> Enum.reject(fn item -> item["name"] == "" or item["name"] == nil end)
    |> Enum.map(fn item ->
      qty = String.to_integer(item["qty"] || "1")
      unit_price = Decimal.new(item["unit_price"] || "0")
      amount = Decimal.mult(unit_price, qty)
      Map.merge(item, %{"qty" => qty, "unit_price" => unit_price, "amount" => amount})
    end)
  end

  # Browser form submissions may send items either as a list or as an indexed map.
  # Normalize both into a stable ordered list of item maps.
  defp normalize_items_params(items_params) when is_list(items_params), do: items_params

  defp normalize_items_params(items_params) when is_map(items_params) do
    items_params
    |> Enum.sort_by(fn {key, _value} ->
      case Integer.parse(to_string(key)) do
        {idx, ""} -> idx
        _ -> :infinity
      end
    end)
    |> Enum.map(fn {_key, value} -> value end)
  end

  defp normalize_items_params(_), do: []

  defp prepare_invoice_params(invoice_params, processed_items, user) do
    service_name = derive_service_name(invoice_params["service_name"], processed_items)

    invoice_params
    |> Map.delete("items")
    |> Map.put("items", processed_items)
    |> Map.put("service_name", service_name)
    |> copy_buyer_from_contract_or_selection(user)
  end

  defp derive_service_name(service_name, _items)
       when is_binary(service_name) and byte_size(service_name) >= 3 do
    service_name
  end

  defp derive_service_name(_service_name, [first_item | _]) do
    candidate = String.trim(to_string(first_item["name"] || ""))
    if byte_size(candidate) >= 3, do: candidate, else: gettext("Services")
  end

  defp derive_service_name(_service_name, _items), do: gettext("Services")

  defp copy_buyer_from_contract_or_selection(invoice_params, user) do
    buyer_id = invoice_params["buyer_id"]
    contract_id = invoice_params["contract_id"]

    cond do
      contract_id && contract_id != "" ->
        case Invoicing.get_invoice_source_contract_for_user(user.id, contract_id) do
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
    contracts = Invoicing.list_invoice_source_contracts_for_user(user.id)
    buyers = Buyers.list_buyers_for_company(company.id)
    bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
    kbe_codes = Payments.list_kbe_codes()
    knp_codes = Payments.list_knp_codes()

    selected_bank_account_id =
      normalize_selected_bank_account_id(invoice_params["bank_account_id"]) ||
        default_bank_account_id(bank_accounts)

    conn
    |> put_flash(:error, error_message)
    |> render(:new,
      page_title: gettext("New Invoice"),
      current_section: :invoices,
      contracts: contracts,
      buyers: buyers,
      bank_accounts: bank_accounts,
      kbe_codes: kbe_codes,
      knp_codes: knp_codes,
      selected_bank_account_id: selected_bank_account_id,
      selected_kbe_code_id:
        normalize_selected_code_id(invoice_params["kbe_code_id"]) ||
          bank_account_kbe_code_id(bank_accounts, selected_bank_account_id) ||
          first_code_id(kbe_codes),
      selected_knp_code_id:
        normalize_selected_code_id(invoice_params["knp_code_id"]) ||
          bank_account_knp_code_id(bank_accounts, selected_bank_account_id) ||
          first_code_id(knp_codes),
      selected_contract_id: invoice_params["contract_id"],
      selected_buyer_id: invoice_params["buyer_id"],
      buyer_address: invoice_params["buyer_address"] || "",
      invoice_type: invoice_params["invoice_type"] || "contract",
      prefill_items: []
    )
  end

  defp default_bank_account_id(bank_accounts) do
    case Enum.find(bank_accounts, & &1.is_default) do
      nil -> nil
      account -> account.id
    end
  end

  defp normalize_selected_bank_account_id(nil), do: nil

  defp normalize_selected_bank_account_id(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp normalize_selected_bank_account_id(value), do: value

  defp normalize_selected_code_id(nil), do: nil

  defp normalize_selected_code_id(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp normalize_selected_code_id(value), do: value

  defp bank_account_kbe_code_id(bank_accounts, bank_account_id) do
    bank_accounts
    |> Enum.find(&(&1.id == bank_account_id))
    |> then(fn account -> account && account.kbe_code_id end)
  end

  defp bank_account_knp_code_id(bank_accounts, bank_account_id) do
    bank_accounts
    |> Enum.find(&(&1.id == bank_account_id))
    |> then(fn account -> account && account.knp_code_id end)
  end

  defp first_code_id([]), do: nil
  defp first_code_id([code | _]), do: code.id

  defp normalize_selected_contract_id(nil), do: nil

  defp normalize_selected_contract_id(contract_id) when is_binary(contract_id) do
    if String.trim(contract_id) == "", do: nil, else: contract_id
  end

  defp normalize_selected_contract_id(_), do: nil

  defp prefill_from_contract(_user_id, nil) do
    %{
      selected_contract_id: nil,
      selected_buyer_id: nil,
      selected_bank_account_id: nil,
      buyer_address: "",
      prefill_items: []
    }
  end

  defp prefill_from_contract(user_id, contract_id) do
    case Invoicing.build_invoice_from_contract(user_id, contract_id) do
      {:ok, data} ->
        data

      _ ->
        %{
          selected_contract_id: nil,
          selected_buyer_id: nil,
          selected_bank_account_id: nil,
          buyer_address: "",
          prefill_items: []
        }
    end
  end

  defp validate_selected_contract(_user_id, contract_id) when contract_id in [nil, ""], do: :ok

  defp validate_selected_contract(user_id, contract_id) do
    case Invoicing.get_invoice_source_contract_for_user(user_id, contract_id) do
      {:ok, _contract} ->
        :ok

      {:error, :not_found} ->
        {:error, gettext("Please select a signed contract.")}

      {:error, :company_required} ->
        {:error, gettext("Please set up your company first.")}
    end
  end

  def pdf(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.get_invoice_for_user(user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, gettext("Invoice not found."))
        |> redirect(to: "/invoices")

      invoice ->
        case PdfRequests.fetch_or_enqueue(:invoice, invoice.id, user.id) do
          {:ok, pdf_binary} ->
            conn
            |> put_layout(false)
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="invoice-#{invoice.number}.pdf")
            )
            |> send_resp(200, pdf_binary)

          {:pending, _reason} ->
            conn
            |> put_flash(
              :info,
              gettext("PDF is being prepared. Please try again in a few seconds.")
            )
            |> redirect(to: "/invoices/#{id}")

          {:error, _reason} ->
            conn
            |> put_status(:internal_server_error)
            |> put_flash(:error, gettext("Failed to generate the PDF file."))
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
          |> put_flash(:info, gettext("Invoice deleted successfully."))
          |> redirect(to: "/invoices")
        end
      end,
      error: fn conn, type, details ->
        cond do
          type == :business_rule && details[:rule] == :cannot_delete_issued_invoice ->
            if UnifiedErrorHandler.htmx_request?(conn) do
              conn
              |> put_resp_content_type("text/html")
              |> send_resp(
                403,
                "<span class='text-red-600'>" <>
                  gettext("Issued invoices cannot be deleted.") <> "</span>"
              )
            else
              conn
              |> put_flash(:error, gettext("Issued invoices cannot be deleted."))
              |> redirect(to: "/invoices")
            end

          true ->
            if UnifiedErrorHandler.htmx_request?(conn) do
              conn
              |> put_resp_content_type("text/html")
              |> send_resp(
                404,
                "<span class='text-red-600'>" <>
                  gettext("Failed to delete invoice.") <> "</span>"
              )
            else
              conn
              |> put_flash(:error, gettext("Failed to delete invoice."))
              |> redirect(to: "/invoices")
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
        |> put_flash(:error, gettext("Invoice not found."))
        |> redirect(to: "/invoices")

      invoice ->
        if InvoiceStatus.is_draft?(invoice.status) do
          changeset = Ecto.Changeset.change(invoice)

          render(conn, :edit,
            invoice: invoice,
            changeset: changeset,
            kbe_codes: Payments.list_kbe_codes(),
            knp_codes: Payments.list_knp_codes(),
            current_section: :invoices,
            page_title: gettext("Edit Invoice %{number}", number: invoice.number)
          )
        else
          conn
          |> put_flash(:error, gettext("Only draft invoices can be edited."))
          |> redirect(to: "/invoices/#{id}")
        end
    end
  end

  def update(conn, %{"id" => id, "invoice" => invoice_params}) do
    user = current_user(conn)

    case Invoicing.update_invoice_for_user(user.id, id, invoice_params) do
      {:ok, invoice} ->
        conn
        |> put_flash(:info, gettext("Invoice updated successfully."))
        |> redirect(to: "/invoices/#{invoice.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        invoice = Invoicing.get_invoice_for_user(user.id, id)

        conn
        |> put_flash(
          :error,
          gettext("Failed to update invoice: %{details}",
            details: ErrorHelpers.format_changeset_errors(changeset)
          )
        )
        |> render(:edit,
          invoice: invoice,
          changeset: changeset,
          kbe_codes: Payments.list_kbe_codes(),
          knp_codes: Payments.list_knp_codes(),
          current_section: :invoices,
          page_title: gettext("Edit Invoice %{number}", number: invoice.number)
        )

      {:error, reason} ->
        invoice = Invoicing.get_invoice_for_user(user.id, id)

        conn
        |> put_flash(
          :error,
          gettext("Failed to update invoice: %{reason}", reason: inspect(reason))
        )
        |> render(:edit,
          invoice: invoice,
          changeset: Ecto.Changeset.change(invoice, invoice_params),
          kbe_codes: Payments.list_kbe_codes(),
          knp_codes: Payments.list_knp_codes(),
          current_section: :invoices,
          page_title: gettext("Edit Invoice %{number}", number: invoice.number)
        )
    end
  end

  def issue(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.issue_invoice_for_user(user.id, id) do
      {:ok, invoice} ->
        conn
        |> put_flash(:info, gettext("Invoice issued successfully."))
        |> redirect(to: "/invoices/#{invoice.id}")

      {:error, {:business_rule, %{rule: :cannot_issue}}} ->
        conn
        |> put_flash(:error, gettext("Only draft invoices can be issued."))
        |> redirect(to: "/invoices/#{id}")

      {:error, {:business_rule, %{rule: :already_issued}}} ->
        conn
        |> put_flash(:error, gettext("Invoice has already been issued."))
        |> redirect(to: "/invoices/#{id}")

      {:error,
       {:business_rule,
        %{rule: :business_rule, details: %{rule: :contract_must_be_signed_to_issue_invoice}}}} ->
        conn
        |> put_flash(
          :error,
          gettext(
            "Invoices linked to a contract can only be issued after the contract is signed."
          )
        )
        |> redirect(to: "/invoices/#{id}")

      {:error, :business_rule,
       %{rule: :business_rule, details: %{rule: :contract_must_be_signed_to_issue_invoice}}} ->
        conn
        |> put_flash(
          :error,
          gettext(
            "Invoices linked to a contract can only be issued after the contract is signed."
          )
        )
        |> redirect(to: "/invoices/#{id}")

      {:error, {:business_rule, %{rule: :contract_must_be_signed_to_issue_invoice}}} ->
        conn
        |> put_flash(
          :error,
          gettext(
            "Invoices linked to a contract can only be issued after the contract is signed."
          )
        )
        |> redirect(to: "/invoices/#{id}")

      {:error, :business_rule, %{rule: :quota_exceeded}} ->
        conn
        |> put_flash(
          :error,
          gettext(
            "Document limit reached for this billing period. Upgrade your plan to continue."
          )
        )
        |> redirect(to: "/invoices/#{id}")

      {:error, {:business_rule, %{rule: :quota_exceeded}}} ->
        conn
        |> put_flash(
          :error,
          gettext(
            "Document limit reached for this billing period. Upgrade your plan to continue."
          )
        )
        |> redirect(to: "/invoices/#{id}")

      {:error, reason} ->
        conn
        |> put_flash(
          :error,
          gettext("Failed to issue invoice: %{reason}", reason: inspect(reason))
        )
        |> redirect(to: "/invoices/#{id}")
    end
  end

  def pay(conn, %{"id" => id}) do
    user = current_user(conn)

    case Invoicing.pay_invoice_for_user(user.id, id) do
      {:ok, invoice} ->
        conn
        |> put_flash(:info, gettext("Invoice marked as paid."))
        |> redirect(to: "/invoices/#{invoice.id}")

      {:error, :business_rule, %{rule: :cannot_mark_paid}} ->
        conn
        |> put_flash(:error, gettext("Only issued invoices can be marked as paid."))
        |> redirect(to: "/invoices/#{id}")

      {:error, :business_rule, %{rule: :already_paid}} ->
        conn
        |> put_flash(:error, gettext("Invoice has already been paid."))
        |> redirect(to: "/invoices/#{id}")

      {:error, :business_rule, %{rule: :contract_must_be_signed_to_pay_invoice}} ->
        conn
        |> put_flash(
          :error,
          gettext(
            "Invoices linked to a contract can only be marked as paid after the contract is signed."
          )
        )
        |> redirect(to: "/invoices/#{id}")

      {:error, {:business_rule, %{rule: :cannot_mark_paid}}} ->
        conn
        |> put_flash(:error, gettext("Only issued invoices can be marked as paid."))
        |> redirect(to: "/invoices/#{id}")

      {:error, {:business_rule, %{rule: :already_paid}}} ->
        conn
        |> put_flash(:error, gettext("Invoice has already been paid."))
        |> redirect(to: "/invoices/#{id}")

      {:error, {:business_rule, %{rule: :contract_must_be_signed_to_pay_invoice}}} ->
        conn
        |> put_flash(
          :error,
          gettext(
            "Invoices linked to a contract can only be marked as paid after the contract is signed."
          )
        )
        |> redirect(to: "/invoices/#{id}")

      {:error, reason} ->
        conn
        |> put_flash(
          :error,
          gettext("Failed to mark invoice as paid: %{reason}", reason: inspect(reason))
        )
        |> redirect(to: "/invoices/#{id}")
    end
  end
end
