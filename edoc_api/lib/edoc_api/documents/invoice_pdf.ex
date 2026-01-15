defmodule EdocApi.Documents.InvoicePdf do
  alias EdocApi.Pdf
  alias EdocApiWeb.PdfTemplates

  @spec render(term()) :: {:ok, binary()} | {:error, term()}
  def render(invoice) do
    invoice
    |> PdfTemplates.invoice_html()
    |> Pdf.html_to_pdf()
  end
end
