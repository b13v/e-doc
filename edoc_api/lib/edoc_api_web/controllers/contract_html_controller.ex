defmodule EdocApiWeb.ContractHTMLController do
  use EdocApiWeb, :controller

  plug(:put_view, EdocApiWeb.ContractHTML)

  alias EdocApi.Core
  alias EdocApi.Buyers
  alias EdocApi.Companies
  alias EdocApi.Payments
  alias EdocApi.ContractStatus
  alias EdocApiWeb.ErrorHelpers

  def index(conn, _params) do
    user = conn.assigns.current_user
    contracts = Core.list_contracts_for_user(user.id)

    render(conn, :index,
      contracts: contracts,
      current_section: :contracts,
      page_title: gettext("Contracts")
    )
  end

  def new(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        buyers = Buyers.list_buyers_for_company(company.id)

        if Enum.empty?(buyers) do
          conn
          |> put_flash(
            :error,
            gettext("Please create at least one buyer before creating a contract.")
          )
          |> redirect(to: "/buyers/new")
        else
          bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
          banks = Payments.list_banks()
          kbe_codes = Payments.list_kbe_codes()
          knp_codes = Payments.list_knp_codes()
          units = Core.list_units_of_measurements()

          render(conn, :new,
            contract: nil,
            buyers: buyers,
            bank_accounts: bank_accounts,
            banks: banks,
            kbe_codes: kbe_codes,
            knp_codes: knp_codes,
            units: units,
            changeset: nil,
            current_section: :contracts,
            page_title: gettext("New Contract")
          )
        end
    end
  end

  def create(conn, %{"contract" => contract_params, "items" => items_params, "action" => action}) do
    user = conn.assigns.current_user

    contract_params =
      if action == "issue" do
        Map.put(contract_params, "status", ContractStatus.issued())
      else
        Map.put(contract_params, "status", ContractStatus.draft())
      end

    create_contract_with_params(conn, user, contract_params, items_params)
  end

  def create(conn, %{"contract" => contract_params, "items" => items_params}) do
    user = conn.assigns.current_user
    create_contract_with_params(conn, user, contract_params, items_params)
  end

  defp create_contract_with_params(conn, user, contract_params, items_params) do
    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        buyers = Buyers.list_buyers_for_company(company.id)
        bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
        banks = Payments.list_banks()
        kbe_codes = Payments.list_kbe_codes()
        knp_codes = Payments.list_knp_codes()
        units = Core.list_units_of_measurements()

        items =
          items_params
          |> normalize_items_params()
          |> Enum.reject(fn item ->
            item["name"] == "" or item["name"] == nil
          end)
          |> Enum.map(fn item ->
            qty = String.to_integer(item["qty"] || "1")
            unit_price = Decimal.new(item["unit_price"] || "0")
            amount = Decimal.mult(unit_price, qty)
            Map.merge(item, %{"qty" => qty, "unit_price" => unit_price, "amount" => amount})
          end)

        case Core.create_contract_for_user(user.id, contract_params, items) do
          {:ok, contract} ->
            conn
            |> put_flash(:info, gettext("Contract created successfully."))
            |> redirect(to: "/contracts/#{contract.id}")

          {:error, :company_required} ->
            conn
            |> put_flash(:error, gettext("Please set up your company first."))
            |> redirect(to: "/company/setup")

          {:error, :business_rule, %{rule: :buyer_required}} ->
            conn
            |> put_flash(:error, gettext("Please select a buyer."))
            |> render(:new,
              contract: nil,
              buyers: buyers,
              bank_accounts: bank_accounts,
              banks: banks,
              kbe_codes: kbe_codes,
              knp_codes: knp_codes,
              units: units,
              changeset: nil,
              current_section: :contracts,
              page_title: gettext("New Contract")
            )

          {:error, :validation, %{changeset: changeset}} ->
            conn
            |> put_flash(:error, contract_validation_message(changeset))
            |> render(:new,
              contract: nil,
              buyers: buyers,
              bank_accounts: bank_accounts,
              banks: banks,
              kbe_codes: kbe_codes,
              knp_codes: knp_codes,
              units: units,
              changeset: changeset,
              current_section: :contracts,
              page_title: gettext("New Contract")
            )

          {:error, reason} when is_atom(reason) or is_binary(reason) ->
            conn
            |> put_flash(
              :error,
              gettext("Failed to create contract: %{reason}", reason: inspect(reason))
            )
            |> render(:new,
              contract: nil,
              buyers: buyers,
              bank_accounts: bank_accounts,
              banks: banks,
              kbe_codes: kbe_codes,
              knp_codes: knp_codes,
              units: units,
              changeset: nil,
              current_section: :contracts,
              page_title: gettext("New Contract")
            )
        end
    end
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.get_contract_for_user(user.id, id) do
      {:error, :not_found, _details} ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, gettext("Contract not found."))
        |> redirect(to: "/contracts")

      {:ok, contract} ->
        require Logger
        Logger.info("Contract #{id} has #{length(contract.contract_items || [])} items")

        seller = build_seller_data(contract)
        buyer = build_buyer_data(contract)
        bank = build_bank_data(contract)
        items = build_items_data(contract)

        Logger.info("Built #{length(items)} items for display")

        totals = build_totals(items, contract.vat_rate)

        render(conn, :show,
          contract: contract,
          seller: seller,
          buyer: buyer,
          bank: bank,
          items: items,
          totals: totals,
          current_section: :contracts,
          page_title: gettext("Contract %{number}", number: contract.number)
        )
    end
  end

  def prefill(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.get_contract_for_user(user.id, id) do
      {:error, :not_found, _details} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "contract_not_found"})

      {:ok, contract} ->
        contract = EdocApi.Repo.preload(contract, [:buyer, :contract_items])

        buyer =
          if contract.buyer do
            %{
              id: contract.buyer.id,
              name: contract.buyer.name,
              bin_iin: contract.buyer.bin_iin,
              address: contract.buyer.address || ""
            }
          else
            %{
              id: nil,
              name: contract.buyer_name,
              bin_iin: contract.buyer_bin_iin,
              address: contract.buyer_address || ""
            }
          end

        items =
          Enum.map(contract.contract_items || [], fn item ->
            %{
              code: item.code || "",
              name: item.name || "",
              qty: item.qty || 1,
              unit_price: Decimal.to_string(item.unit_price || Decimal.new(0))
            }
          end)

        json(conn, %{
          buyer: buyer,
          items: items
        })
    end
  end

  def edit(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.get_contract_for_user(user.id, id) do
      {:error, :not_found, _details} ->
        conn
        |> put_flash(:error, gettext("Contract not found."))
        |> redirect(to: "/contracts")

      {:ok, contract} ->
        if ContractStatus.is_issued?(contract) do
          conn
          |> put_flash(:error, gettext("Issued contracts cannot be edited."))
          |> redirect(to: "/contracts/#{id}")
        else
          case Companies.get_company_by_user_id(user.id) do
            nil ->
              conn
              |> put_flash(:error, gettext("Please set up your company first."))
              |> redirect(to: "/company/setup")

            company ->
              buyers = Buyers.list_buyers_for_company(company.id)
              bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
              banks = Payments.list_banks()
              kbe_codes = Payments.list_kbe_codes()
              knp_codes = Payments.list_knp_codes()
              units = Core.list_units_of_measurements()

              render(conn, :edit,
                contract: contract,
                buyers: buyers,
                bank_accounts: bank_accounts,
                banks: banks,
                kbe_codes: kbe_codes,
                knp_codes: knp_codes,
                units: units,
                current_section: :contracts,
                page_title: gettext("Edit Contract %{number}", number: contract.number)
              )
          end
        end
    end
  end

  def update(conn, %{"id" => id, "contract" => contract_params} = params) do
    items_params = Map.get(params, "items", [])
    do_update(conn, id, contract_params, items_params)
  end

  defp do_update(conn, id, contract_params, items_params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        buyers = Buyers.list_buyers_for_company(company.id)
        bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
        units = Core.list_units_of_measurements()

        items =
          items_params
          |> normalize_items_params()
          |> Enum.reject(fn item ->
            item["name"] == "" or item["name"] == nil
          end)
          |> Enum.map(fn item ->
            qty = String.to_integer(item["qty"] || "1")
            unit_price = Decimal.new(item["unit_price"] || "0")
            amount = Decimal.mult(unit_price, qty)
            Map.merge(item, %{"qty" => qty, "unit_price" => unit_price, "amount" => amount})
          end)

        case Core.update_contract_for_user(user.id, id, contract_params, items) do
          {:ok, contract} ->
            conn
            |> put_flash(:info, gettext("Contract updated successfully."))
            |> redirect(to: "/contracts/#{contract.id}")

          {:error, :not_found, _details} ->
            conn
            |> put_flash(:error, gettext("Contract not found."))
            |> redirect(to: "/contracts")

          {:error, :business_rule, %{rule: rule}}
          when rule in [:contract_not_editable, :contract_already_issued] ->
            conn
            |> put_flash(:error, gettext("This contract cannot be edited."))
            |> redirect(to: "/contracts/#{id}")

          {:error, :validation, %{changeset: changeset}} ->
            contract = Core.get_contract_for_user(user.id, id) |> elem(1)

            conn
            |> put_flash(:error, contract_validation_message(changeset))
            |> render(:edit,
              contract: contract,
              buyers: buyers,
              bank_accounts: bank_accounts,
              units: units,
              current_section: :contracts,
              page_title: gettext("Edit Contract")
            )

          {:error, reason} when is_atom(reason) or is_binary(reason) ->
            contract = Core.get_contract_for_user(user.id, id) |> elem(1)

            conn
            |> put_flash(
              :error,
              gettext("Failed to update contract: %{reason}", reason: inspect(reason))
            )
            |> render(:edit,
              contract: contract,
              buyers: buyers,
              bank_accounts: bank_accounts,
              units: units,
              current_section: :contracts,
              page_title: gettext("Edit Contract")
            )
        end
    end
  end

  def pdf(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.get_contract_for_user(user.id, id) do
      {:error, :not_found, _details} ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, gettext("Contract not found."))
        |> redirect(to: "/contracts")

      {:ok, contract} ->
        # Pre-render HTML in web layer, then pass to PDF module
        html = EdocApiWeb.PdfTemplates.contract_html(contract)

        case EdocApi.Documents.ContractPdf.render(html) do
          {:ok, pdf_binary} ->
            conn
            |> put_layout(false)
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="contract-#{contract.number}.pdf")
            )
            |> send_resp(200, pdf_binary)

          {:error, _reason} ->
            conn
            |> put_status(:internal_server_error)
            |> put_flash(:error, gettext("Failed to generate the PDF file."))
            |> redirect(to: "/contracts/#{id}")
        end
    end
  end

  def issue(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.issue_contract_for_user(user.id, id) do
      {:ok, _contract} ->
        conn
        |> put_flash(:info, gettext("Contract issued successfully."))
        |> redirect(to: "/contracts/#{id}")

      {:error, :not_found, _details} ->
        conn
        |> put_flash(:error, gettext("Contract not found."))
        |> redirect(to: "/contracts")

      {:error, :business_rule, %{rule: :buyer_required}} ->
        conn
        |> put_flash(:error, gettext("Please add buyer details before issuing."))
        |> redirect(to: "/contracts/#{id}/edit")

      {:error, :business_rule, %{rule: rule}}
      when rule in [:contract_already_issued, :contract_not_editable] ->
        conn
        |> put_flash(:error, gettext("This contract cannot be issued."))
        |> redirect(to: "/contracts/#{id}")

      {:error, reason} ->
        conn
        |> put_flash(
          :error,
          gettext("Failed to issue contract: %{reason}", reason: inspect(reason))
        )
        |> redirect(to: "/contracts/#{id}")
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.delete_contract_for_user(user.id, id) do
      {:ok, _contract} ->
        conn
        |> put_flash(:info, gettext("Contract deleted successfully."))
        |> redirect(to: "/contracts")

      {:error, :not_found, _details} ->
        conn
        |> put_flash(:error, gettext("Contract not found."))
        |> redirect(to: "/contracts")

      {:error, :business_rule, %{rule: rule}}
      when rule in [:contract_not_editable, :contract_already_issued] ->
        conn
        |> put_flash(:error, gettext("Only draft contracts can be deleted."))
        |> redirect(to: "/contracts/#{id}")

      {:error, reason} ->
        conn
        |> put_flash(
          :error,
          gettext("Failed to delete contract: %{reason}", reason: inspect(reason))
        )
        |> redirect(to: "/contracts/#{id}")
    end
  end

  defp build_seller_data(contract),
    do: EdocApi.Documents.Builders.ContractDataBuilder.build_seller_data(contract)

  defp build_buyer_data(contract),
    do: EdocApi.Documents.Builders.ContractDataBuilder.build_buyer_data(contract)

  defp build_bank_data(contract),
    do: EdocApi.Documents.Builders.ContractDataBuilder.build_bank_data(contract)

  defp build_items_data(contract),
    do: EdocApi.Documents.Builders.ContractDataBuilder.build_items_data(contract)

  defp build_totals(items, vat_rate),
    do: EdocApi.Documents.Builders.ContractDataBuilder.build_totals(items, vat_rate)

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

  defp contract_validation_message(changeset) do
    has_duplicate_number_error? =
      Enum.any?(changeset.errors, fn
        {:number, {"has already been taken", _opts}} -> true
        _ -> false
      end)

    if has_duplicate_number_error? do
      gettext("A contract with this number already exists.")
    else
      gettext("Validation failed: %{details}",
        details: ErrorHelpers.format_changeset_errors(changeset)
      )
    end
  end
end
