defmodule EdocApi.Documents.Builders.ContractDataBuilder do
  @moduledoc """
  Builds data maps for contract PDF rendering.

  These pure functions extract and format data from contract structs
  for use in PDF templates. They can be called from both controllers
  (for display) and PdfTemplates (for PDF generation).
  """

  alias EdocApi.LegalForms

  @doc """
  Builds seller data from contract's company.
  """
  def build_seller_data(contract) do
    company = contract.company || %{}

    %{
      name: first_present([Map.get(company, :name), contract.company_id]) || "",
      legal_form: LegalForms.display(Map.get(company, :legal_form)),
      bin_iin: first_present([Map.get(company, :bin_iin)]) || "",
      city: first_present([Map.get(company, :city), contract.city]) || "",
      address: first_present([Map.get(company, :address)]) || "",
      director_name: first_present([Map.get(company, :representative_name)]) || "",
      director_title: first_present([Map.get(company, :representative_title)]) || "директор",
      basis: "Устав",
      phone: first_present([Map.get(company, :phone)]) || "",
      email: first_present([Map.get(company, :email)]) || ""
    }
  end

  @doc """
  Builds buyer data from contract's buyer association or legacy fields.
  """
  def build_buyer_data(contract) do
    case contract.buyer do
      %Ecto.Association.NotLoaded{} -> build_buyer_from_legacy_fields(contract)
      nil -> build_buyer_from_legacy_fields(contract)
      _buyer -> build_buyer_from_association(contract)
    end
  end

  @doc """
  Builds bank data from contract's bank_account.
  """
  def build_bank_data(contract) do
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

  @doc """
  Builds items list from contract's contract_items.
  """
  def build_items_data(contract) do
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

  @doc """
  Builds totals (subtotal, vat, total) from items and vat_rate.
  """
  def build_totals(items, vat_rate) do
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

  # Private helpers

  defp build_buyer_from_association(contract) do
    buyer_entity = contract.buyer
    buyer_bank_account = default_buyer_bank_account(buyer_entity)
    buyer_bank = if buyer_bank_account, do: buyer_bank_account.bank, else: nil

    %{
      name: first_present([buyer_entity.name]) || "",
      legal_form: LegalForms.display(buyer_entity.legal_form || contract.buyer_legal_form),
      bin_iin: first_present([buyer_entity.bin_iin]) || "",
      city: first_present([buyer_entity.city]) || "",
      address: first_present([buyer_entity.address]) || "",
      director_name:
        first_present([buyer_entity.director_name, contract.buyer_director_name]) || "",
      director_title:
        first_present([buyer_entity.director_title, contract.buyer_director_title]) || "директор",
      basis: first_present([buyer_entity.basis, contract.buyer_basis]) || "Устав",
      phone: first_present([buyer_entity.phone, contract.buyer_phone]) || "",
      email: first_present([buyer_entity.email, contract.buyer_email]) || "",
      bank_name: if(buyer_bank, do: buyer_bank.name || "", else: ""),
      iban: if(buyer_bank_account, do: buyer_bank_account.iban || "", else: ""),
      bic:
        cond do
          buyer_bank_account && buyer_bank_account.bic ->
            buyer_bank_account.bic

          buyer_bank ->
            buyer_bank.bic || ""

          true ->
            ""
        end
    }
  end

  defp build_buyer_from_legacy_fields(contract) do
    %{
      name: first_present([contract.buyer_name]) || "",
      legal_form: LegalForms.display(contract.buyer_legal_form),
      bin_iin: first_present([contract.buyer_bin_iin]) || "",
      city: "",
      address: first_present([contract.buyer_address]) || "",
      director_name: first_present([contract.buyer_director_name]) || "",
      director_title: first_present([contract.buyer_director_title]) || "директор",
      basis: first_present([contract.buyer_basis]) || "Устав",
      phone: first_present([contract.buyer_phone]) || "",
      email: first_present([contract.buyer_email]) || "",
      bank_name: "",
      iban: "",
      bic: ""
    }
  end

  defp default_buyer_bank_account(buyer) do
    bank_accounts =
      case buyer.bank_accounts do
        %Ecto.Association.NotLoaded{} -> []
        accounts -> accounts
      end

    Enum.find(bank_accounts, & &1.is_default) || List.first(bank_accounts)
  end

  defp first_present(values) do
    Enum.find_value(values, fn
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      nil ->
        nil

      value ->
        value
    end)
  end
end
