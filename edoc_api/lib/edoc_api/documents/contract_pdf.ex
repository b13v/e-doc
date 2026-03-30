defmodule EdocApi.Documents.ContractPdf do
  @moduledoc """
  Renders contract HTML to PDF.

  HTML must be pre-rendered by the web layer using PdfTemplates.
  This module only handles the conversion to PDF binary.
  """

  alias EdocApi.Pdf

  @spec render(binary()) :: {:ok, binary()} | {:error, term()}
  def render(html) when is_binary(html) do
    Pdf.html_to_pdf(html)
  end
end
