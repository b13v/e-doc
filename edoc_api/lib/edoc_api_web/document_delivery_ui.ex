defmodule EdocApiWeb.DocumentDeliveryUI do
  alias EdocApi.ContractStatus
  alias EdocApi.DocumentDelivery.DocumentRenderer
  alias EdocApi.DocumentDelivery.DocumentResolver
  alias EdocApi.InvoiceStatus

  def sendable?(document_type, document) do
    case normalize_type(document_type) do
      :invoice -> not InvoiceStatus.is_draft?(document)
      :contract -> not ContractStatus.is_draft?(document)
      :act -> true
    end
  end

  def recipient_defaults(document_type, document) do
    case normalize_type(document_type) do
      :invoice ->
        contract = Map.get(document, :contract)
        buyer = contract && Map.get(contract, :buyer)

        %{
          recipient_name: document.buyer_name || nested_value(contract, :buyer_name) || "",
          recipient_email:
            nested_value(buyer, :email) || nested_value(contract, :buyer_email) || ""
        }

      :contract ->
        buyer = Map.get(document, :buyer)

        %{
          recipient_name: nested_value(buyer, :name) || document.buyer_name || "",
          recipient_email: nested_value(buyer, :email) || document.buyer_email || ""
        }

      :act ->
        buyer = Map.get(document, :buyer)

        %{
          recipient_name: nested_value(buyer, :name) || document.buyer_name || "",
          recipient_email: nested_value(buyer, :email) || ""
        }
    end
  end

  def document_title(document_type, document) do
    DocumentRenderer.title(normalize_type(document_type), document)
  end

  def show_path(document_type, document_id) do
    case normalize_type(document_type) do
      :invoice -> "/invoices/#{document_id}"
      :contract -> "/contracts/#{document_id}"
      :act -> "/acts/#{document_id}"
    end
  end

  def send_email_path(document_type, document_id) do
    "/documents/#{normalize_type(document_type)}/#{document_id}/send/email"
  end

  def share_path(document_type, document_id, channel) do
    "/documents/#{normalize_type(document_type)}/#{document_id}/share/#{channel}"
  end

  def normalize_type(document_type) do
    case DocumentResolver.normalize_document_type(document_type) do
      {:ok, normalized_type} -> normalized_type
      _ -> :invoice
    end
  end

  defp nested_value(nil, _field), do: nil
  defp nested_value(data, field), do: Map.get(data, field)
end
