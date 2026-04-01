defmodule EdocApi.DocumentDeliveryTest do
  use EdocApi.DataCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.DocumentDelivery
  alias EdocApi.DocumentDelivery.EmailBuilder

  describe "public access tokens" do
    test "creates a hashed token and resolves a public invoice document" do
      user = create_user!()
      company = create_company!(user)
      invoice = create_invoice_with_items!(user, company)

      assert {:ok, token_data} =
               DocumentDelivery.create_public_access_token(user.id, :invoice, invoice.id,
                 ttl_seconds: 3600
               )

      assert is_binary(token_data.token)
      assert token_data.token != ""
      assert token_data.url =~ "/public/docs/"
      assert token_data.public_access_token.document_type == "invoice"
      refute token_data.public_access_token.token_hash == token_data.token

      assert {:ok, public_document} = DocumentDelivery.get_public_document(token_data.token)
      assert public_document.document_type == "invoice"
      assert public_document.title =~ invoice.number
      assert public_document.pdf_path == "/public/docs/#{token_data.token}/pdf"
    end

    test "revoked tokens cannot be resolved" do
      user = create_user!()
      company = create_company!(user)
      invoice = create_invoice_with_items!(user, company)

      assert {:ok, token_data} =
               DocumentDelivery.create_public_access_token(user.id, :invoice, invoice.id,
                 ttl_seconds: 3600
               )

      assert {:ok, _token} =
               DocumentDelivery.revoke_public_access_token(
                 user.id,
                 token_data.public_access_token.id
               )

      assert {:error, :public_token_not_found} =
               DocumentDelivery.get_public_document(token_data.token)
    end
  end

  describe "email builder localization" do
    test "builds Kazakh subject and body when locale is kk" do
      email =
        EmailBuilder.build(
          :contract,
          %{number: "26-03/01"},
          "%PDF-1.4",
          "http://localhost:4000/public/docs/token",
          %{
            "recipient_name" => "Buyer LLC",
            "recipient_email" => "buyer@example.com",
            "locale" => "kk"
          }
        )

      assert email.subject =~ "Келісімшарт № 26-03/01"
      assert email.text_body =~ "Қосымшада және қорғалған сілтеме арқылы құжатты жолдаймыз:"

      assert email.text_body =~
               "Email ресми жіберу арнасы болып табылады. Мессенджерлер тек қосымша ыңғайлы хабарлау арнасы ретінде пайдаланылады."

      assert email.html_body =~ "Қосымшада және қорғалған сілтеме арқылы құжатты жолдаймыз:"

      refute email.subject =~ "Договор № 26-03/01"
      refute email.text_body =~ "Направляем вам документ во вложении и по защищенной ссылке:"
    end
  end
end
