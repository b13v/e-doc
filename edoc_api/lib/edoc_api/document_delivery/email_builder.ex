defmodule EdocApi.DocumentDelivery.EmailBuilder do
  import Swoosh.Email

  alias EdocApi.DocumentDelivery.DocumentRenderer
  alias Swoosh.Attachment

  @from {"EdocAPI", System.get_env("EMAIL_FROM") || "noreply@edocapi.com"}

  def build(document_type, document, pdf_binary, public_link, attrs \\ %{}) do
    recipient_email = Map.get(attrs, :recipient_email) || Map.get(attrs, "recipient_email")
    recipient_name = Map.get(attrs, :recipient_name) || Map.get(attrs, "recipient_name")

    title = DocumentRenderer.title(document_type, document)
    filename = DocumentRenderer.filename(document_type, document)

    new()
    |> to({recipient_name, recipient_email})
    |> from(@from)
    |> subject("#{title} - EdocAPI")
    |> text_body(email_text_body(title, public_link))
    |> html_body(email_html_body(title, public_link))
    |> attachment(
      Attachment.new({:data, pdf_binary},
        filename: filename,
        content_type: "application/pdf"
      )
    )
  end

  defp email_text_body(title, public_link) do
    """
    #{title}

    Направляем вам документ во вложении и по защищенной ссылке:
    #{public_link}

    Email является официальным каналом отправки. Мессенджеры используются только как дополнительный удобный канал уведомления.
    """
  end

  defp email_html_body(title, public_link) do
    """
    <html>
      <body>
        <p><strong>#{title}</strong></p>
        <p>Направляем вам документ во вложении и по защищенной ссылке:</p>
        <p><a href="#{public_link}">#{public_link}</a></p>
        <p>Email является официальным каналом отправки. Мессенджеры используются только как дополнительный удобный канал уведомления.</p>
      </body>
    </html>
    """
  end
end
