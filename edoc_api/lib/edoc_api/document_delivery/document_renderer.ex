defmodule EdocApi.DocumentDelivery.DocumentRenderer do
  @moduledoc """
  Provides metadata for document delivery (email, public links).

  PDF rendering is now done in the web layer - see the respective controllers.
  This module only provides document metadata for email attachments and filenames.
  """

  alias EdocApi.Documents.ActPdf
  alias EdocApi.Documents.ContractPdf
  alias EdocApi.Documents.InvoicePdf

  @deprecated "Use EdocApi.Documents.InvoicePdf.render(html_binary) directly in controllers"
  def render(:invoice, invoice), do: InvoicePdf.render(invoice)

  @deprecated "Use EdocApi.Documents.ContractPdf.render(html_binary) directly in controllers"
  def render(:contract, contract), do: ContractPdf.render(contract)

  @deprecated "Use EdocApi.Documents.ActPdf.render(html_binary) directly in controllers"
  def render(:act, act), do: ActPdf.render(act)

  def title(:invoice, invoice), do: "Счет на оплату № #{invoice.number}"
  def title(:contract, contract), do: "Договор № #{contract.number}"
  def title(:act, act), do: "Акт № #{act.number}"

  def filename(:invoice, invoice), do: "invoice-#{invoice.number}.pdf"
  def filename(:contract, contract), do: "contract-#{contract.number}.pdf"
  def filename(:act, act), do: "act-#{act.number}.pdf"

  def public_document(document_type, document, raw_token) do
    %{
      document_type: Atom.to_string(document_type),
      document_number: Map.get(document, :number),
      title: title(document_type, document),
      issue_date: Map.get(document, :issue_date),
      seller_name: Map.get(document, :seller_name) || nested_name(document, :company),
      buyer_name: Map.get(document, :buyer_name) || nested_name(document, :buyer),
      pdf_path: "/public/docs/#{raw_token}/pdf"
    }
  end

  defp nested_name(document, association) do
    case Map.get(document, association) do
      %{name: name} -> name
      _ -> nil
    end
  end
end
