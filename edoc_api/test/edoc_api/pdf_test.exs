defmodule EdocApi.PdfTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Pdf
  alias EdocApiWeb.PdfTemplates
  alias EdocApi.Repo

  import EdocApi.TestFixtures

  if System.find_executable("wkhtmltopdf") do
    test "generates a PDF from invoice html" do
      user = create_user!()
      company = create_company!(user)
      create_company_bank_account!(company)

      invoice =
        user
        |> create_invoice_with_items!(company)
        |> Repo.preload([:company, bank_account: [:bank, :kbe_code, :knp_code]])

      html = PdfTemplates.invoice_html(invoice)

      assert is_binary(html)
      assert {:ok, pdf_binary} = Pdf.html_to_pdf(html)
      assert byte_size(pdf_binary) > 0
    end

    test "generates a PDF from contract html" do
      user = create_user!()
      company = create_company!(user)
      contract = create_contract!(company)

      contract = Repo.preload(contract, :company)
      html = PdfTemplates.contract_html(contract)

      assert is_binary(html)
      assert {:ok, pdf_binary} = Pdf.html_to_pdf(html)
      assert byte_size(pdf_binary) > 0
    end
  else
    @tag skip: "wkhtmltopdf is not available in PATH"
    test "generates a PDF from invoice html" do
      assert true
    end
  end
end
