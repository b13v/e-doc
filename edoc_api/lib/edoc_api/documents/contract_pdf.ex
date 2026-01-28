defmodule EdocApi.Documents.ContractPdf do
  alias EdocApi.Pdf
  alias EdocApiWeb.PdfTemplates

  @spec render(term()) :: {:ok, binary()} | {:error, term()}
  def render(contract) do
    contract
    |> PdfTemplates.contract_html()
    |> Pdf.html_to_pdf()
  end
end
