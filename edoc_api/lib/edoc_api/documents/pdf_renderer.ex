defmodule EdocApi.Documents.PdfRenderer do
  @moduledoc """
  Renders documents to PDF for use in core contexts (e.g., email delivery).

  This module bridges the gap between core and web by importing the web layer's
  PdfTemplates. It's intentionally placed in `documents/` to keep the coupling
  isolated to this single module.

  For web controllers, prefer rendering HTML directly with PdfTemplates and then
  calling the PDF modules (ContractPdf, InvoicePdf, ActPdf) to avoid the
  circular dependency.
  """

  alias EdocApi.Documents.ActPdf
  alias EdocApi.Documents.ContractPdf
  alias EdocApi.Documents.InvoicePdf

  # We need to import PdfTemplates from web layer for HTML rendering
  # This is the ONLY place in core that depends on web
  alias EdocApiWeb.PdfTemplates

  @type document_type :: :contract | :invoice | :act

  @doc """
  Renders a document to PDF binary.

  This is primarily used by the DocumentDelivery context for email attachments.
  Web controllers should use PdfTemplates directly followed by the specific PDF module.
  """
  @spec render(document_type(), term()) :: {:ok, binary()} | {:error, term()}
  def render(:contract, contract), do: ContractPdf.render(PdfTemplates.contract_html(contract))
  def render(:invoice, invoice), do: InvoicePdf.render(PdfTemplates.invoice_html(invoice))
  def render(:act, act), do: ActPdf.render(PdfTemplates.act_html(act))
end
