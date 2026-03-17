defmodule EdocApi.Documents.ActPdf do
  alias EdocApi.Pdf
  alias EdocApiWeb.PdfTemplates

  @spec render(term()) :: {:ok, binary()} | {:error, term()}
  def render(act) do
    act
    |> PdfTemplates.act_html()
    |> Pdf.html_to_pdf(orientation: :landscape)
  end
end
