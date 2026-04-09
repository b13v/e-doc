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

    test "signed contract html includes signed watermark" do
      user = create_user!()
      company = create_company!(user)
      contract = create_contract!(company, %{"status" => "signed"})

      contract = Repo.preload(contract, :company)
      html = PdfTemplates.contract_html(contract)

      assert html =~ "Подписан - Қол қойылған"
    end

    test "signed act html includes signed watermark" do
      user = create_user!()
      company = create_company!(user)

      {:ok, buyer} =
        EdocApi.Buyers.create_buyer_for_company(company.id, %{
          "name" => "Act Buyer",
          "bin_iin" => "080215385677",
          "address" => "Buyer Address"
        })

      {:ok, act} =
        EdocApi.Acts.create_act_for_user(user.id, company.id, %{
          "issue_date" => Date.utc_today(),
          "buyer_id" => buyer.id,
          "buyer_address" => "Buyer Address",
          "items" => [
            %{"name" => "Services", "code" => "A-1", "qty" => "1", "unit_price" => "100.00"}
          ]
        })

      act =
        act
        |> Ecto.Changeset.change(status: "signed")
        |> Repo.update!()

      html = PdfTemplates.act_html(act)

      assert html =~ "Подписан - Қол қойылған"
      assert html =~ "top: 50%;"
      assert html =~ "left: 0;"
      assert html =~ "right: 0;"
      assert html =~ "margin-top: -28px;"
      assert html =~ "transform: rotate(-24deg);"
      refute html =~ "border: 6px solid"
      refute html =~ "padding: 18px 28px"
    end
  else
    @tag skip: "wkhtmltopdf is not available in PATH"
    test "generates a PDF from invoice html" do
      assert true
    end
  end
end
