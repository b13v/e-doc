defmodule EdocApiWeb.ContractsController do
  use EdocApiWeb, :controller

  alias EdocApi.Core
  alias EdocApi.Documents.ContractPdf

  def index(conn, _params) do
    user = conn.assigns.current_user
    contracts = Core.list_contracts_for_user(user.id)
    render(conn, :index, contracts: contracts, page_title: "Contracts")
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.get_contract_for_user(user.id, id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Contract not found")
        |> redirect(to: "/contracts")

      {:ok, contract} ->
        # Prepare data for the legal contract template
        seller = build_seller_data(contract)
        buyer = build_buyer_data(contract)
        bank = build_bank_data(contract)
        items = build_items_data(contract)
        totals = build_totals(items, contract.vat_rate)

        render(conn, :show,
          contract: contract,
          seller: seller,
          buyer: buyer,
          bank: bank,
          items: items,
          totals: totals,
          page_title: "Contract #{contract.number}"
        )
    end
  end

  def pdf(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.get_contract_for_user(user.id, id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Contract not found")
        |> redirect(to: "/contracts")

      {:ok, contract} ->
        case ContractPdf.render(contract) do
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
            |> put_flash(:error, "Failed to generate PDF")
            |> redirect(to: "/contracts/#{id}")
        end
    end
  end

  # Helper functions to build data for the contract template
  defp build_seller_data(contract) do
    company = contract.company || %{}

    %{
      name: Map.get(company, :name) || contract.company_id || "",
      legal_form: "ТОО",
      bin_iin: Map.get(company, :bin_iin) || "",
      address: Map.get(company, :address) || "",
      director_name: Map.get(company, :representative_name) || "",
      director_title: "директор",
      basis: "Устав",
      phone: Map.get(company, :phone) || "",
      email: Map.get(company, :email) || ""
    }
  end

  defp build_buyer_data(contract) do
    if contract.buyer_company do
      company = contract.buyer_company

      %{
        name: Map.get(company, :name) || "",
        legal_form: contract.buyer_legal_form || "ТОО",
        bin_iin: Map.get(company, :bin_iin) || "",
        address: Map.get(company, :address) || "",
        director_name:
          Map.get(company, :representative_name) || contract.buyer_director_name || "",
        director_title: "директор",
        basis: Map.get(company, :basis) || contract.buyer_basis || "Устав",
        phone: Map.get(company, :phone) || contract.buyer_phone || "",
        email: Map.get(company, :email) || contract.buyer_email || ""
      }
    else
      %{
        name: contract.buyer_name || "",
        legal_form: contract.buyer_legal_form || "ТОО",
        bin_iin: contract.buyer_bin_iin || "",
        address: contract.buyer_address || "",
        director_name: contract.buyer_director_name || "",
        director_title: contract.buyer_director_title || "директор",
        basis: contract.buyer_basis || "Устав",
        phone: contract.buyer_phone || "",
        email: contract.buyer_email || ""
      }
    end
  end

  defp build_bank_data(contract) do
    if contract.bank_account do
      acc = contract.bank_account
      bank = acc.bank || %{}
      kbe = acc.kbe_code || %{}
      knp = acc.knp_code || %{}

      %{
        bank_name: Map.get(bank, :name) || "",
        iban: Map.get(acc, :iban) || "",
        bic: Map.get(bank, :bic) || "",
        kbe: Map.get(kbe, :code) || "",
        knp: Map.get(knp, :code) || ""
      }
    else
      %{
        bank_name: "",
        iban: "",
        bic: "",
        kbe: "",
        knp: ""
      }
    end
  end

  defp build_items_data(contract) do
    Enum.map(contract.contract_items || [], fn item ->
      %{
        name: Map.get(item, :name) || "",
        qty: Map.get(item, :qty) || Decimal.new(0),
        unit_price: Map.get(item, :unit_price) || Decimal.new(0),
        amount: Map.get(item, :amount) || Decimal.new(0),
        code: Map.get(item, :code)
      }
    end)
  end

  defp build_totals(items, vat_rate) do
    subtotal =
      Enum.reduce(items, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, item.amount || Decimal.new(0))
      end)

    vat_rate_dec = Decimal.new(vat_rate || 0)

    vat =
      Decimal.mult(subtotal, vat_rate_dec) |> Decimal.div(Decimal.new(100)) |> Decimal.round(2)

    total = Decimal.add(subtotal, vat)

    %{
      subtotal: subtotal,
      vat: vat,
      total: total
    }
  end
end
