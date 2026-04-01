defmodule EdocApi.DocumentDelivery.EmailBuilder do
  import Swoosh.Email

  alias EdocApi.DocumentDelivery.DocumentRenderer
  alias Swoosh.Attachment

  @from {"EdocAPI", System.get_env("EMAIL_FROM") || "noreply@edocapi.com"}

  def build(document_type, document, pdf_binary, public_link, attrs \\ %{}) do
    recipient_email = Map.get(attrs, :recipient_email) || Map.get(attrs, "recipient_email")
    recipient_name = Map.get(attrs, :recipient_name) || Map.get(attrs, "recipient_name")
    locale = normalize_locale(Map.get(attrs, :locale) || Map.get(attrs, "locale"))

    title = localized_title(document_type, document, locale)
    filename = DocumentRenderer.filename(document_type, document)

    new()
    |> to({recipient_name, recipient_email})
    |> from(@from)
    |> subject("#{title} - EdocAPI")
    |> text_body(email_text_body(locale, title, public_link))
    |> html_body(email_html_body(locale, title, public_link))
    |> attachment(
      Attachment.new({:data, pdf_binary},
        filename: filename,
        content_type: "application/pdf"
      )
    )
  end

  defp email_text_body("kk", title, public_link) do
    """
    #{title}

    Қосымшада және қорғалған сілтеме арқылы құжатты жолдаймыз:
    #{public_link}

    Email ресми жіберу арнасы болып табылады. Мессенджерлер тек қосымша ыңғайлы хабарлау арнасы ретінде пайдаланылады.
    """
  end

  defp email_text_body(_locale, title, public_link) do
    """
    #{title}

    Направляем вам документ во вложении и по защищенной ссылке:
    #{public_link}

    Email является официальным каналом отправки. Мессенджеры используются только как дополнительный удобный канал уведомления.
    """
  end

  defp email_html_body("kk", title, public_link) do
    """
    <html>
      <body>
        <p><strong>#{title}</strong></p>
        <p>Қосымшада және қорғалған сілтеме арқылы құжатты жолдаймыз:</p>
        <p><a href="#{public_link}">#{public_link}</a></p>
        <p>Email ресми жіберу арнасы болып табылады. Мессенджерлер тек қосымша ыңғайлы хабарлау арнасы ретінде пайдаланылады.</p>
      </body>
    </html>
    """
  end

  defp email_html_body(_locale, title, public_link) do
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

  defp localized_title(:invoice, invoice, "kk"), do: "Төлем шоты № #{invoice.number}"
  defp localized_title(:contract, contract, "kk"), do: "Келісімшарт № #{contract.number}"
  defp localized_title(:act, act, "kk"), do: "Акт № #{act.number}"
  defp localized_title(document_type, document, _locale), do: DocumentRenderer.title(document_type, document)

  defp normalize_locale(nil), do: "ru"
  defp normalize_locale("kk"), do: "kk"
  defp normalize_locale(_locale), do: "ru"
end
