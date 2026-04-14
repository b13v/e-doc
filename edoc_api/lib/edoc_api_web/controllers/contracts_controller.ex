defmodule EdocApiWeb.ContractsController do
  use EdocApiWeb, :controller

  alias EdocApi.Core
  alias EdocApi.Documents.ContractPdf
  alias EdocApi.Documents.Builders.ContractDataBuilder

  def index(conn, _params) do
    user = conn.assigns.current_user
    contracts = Core.list_contracts_for_user(user.id)
    render(conn, :index, contracts: contracts, page_title: "Contracts")
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Core.get_contract_for_user(user.id, id) do
      {:error, :not_found, _details} ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Контракт не найден.")
        |> redirect(to: "/contracts")

      {:ok, contract} ->
        # Prepare data for the legal contract template
        seller = ContractDataBuilder.build_seller_data(contract)
        buyer = ContractDataBuilder.build_buyer_data(contract)
        bank = ContractDataBuilder.build_bank_data(contract)
        items = ContractDataBuilder.build_items_data(contract)
        totals = ContractDataBuilder.build_totals(items, contract.vat_rate)

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
      {:error, :not_found, _details} ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Контракт не найден.")
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
end
