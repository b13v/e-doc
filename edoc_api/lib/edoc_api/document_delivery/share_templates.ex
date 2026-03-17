defmodule EdocApi.DocumentDelivery.ShareTemplates do
  alias EdocApi.DocumentDelivery.DocumentRenderer

  def build(channel, locale, document_type, document, public_link, recipient_name \\ nil) do
    with {:ok, normalized_channel} <- normalize_channel(channel) do
      text = share_text(locale, document_type, document, public_link, recipient_name)

      {:ok,
       %{
         channel: Atom.to_string(normalized_channel),
         title: DocumentRenderer.title(document_type, document),
         share_text: text,
         share_url: share_url(normalized_channel, text, public_link)
       }}
    end
  end

  def normalize_channel(channel) when channel in [:whatsapp, :telegram], do: {:ok, channel}

  def normalize_channel(channel) when is_binary(channel) do
    case String.downcase(String.trim(channel)) do
      "whatsapp" -> {:ok, :whatsapp}
      "telegram" -> {:ok, :telegram}
      _ -> {:error, :unsupported_share_channel}
    end
  end

  def normalize_channel(_), do: {:error, :unsupported_share_channel}

  defp share_text(locale, document_type, document, public_link, recipient_name) do
    greeting =
      case {normalize_locale(locale), recipient_name} do
        {"kk", name} when is_binary(name) and name != "" -> "Сәлеметсіз бе, #{name}!"
        {"kk", _} -> "Сәлеметсіз бе!"
        {"ru", name} when is_binary(name) and name != "" -> "Здравствуйте, #{name}!"
        _ -> "Здравствуйте!"
      end

    body = share_body(normalize_locale(locale), document_type, document)

    [
      greeting,
      body,
      "Ссылка для просмотра и скачивания PDF: #{public_link}",
      share_disclaimer(normalize_locale(locale))
    ]
    |> Enum.join("\n")
  end

  defp share_body("kk", :invoice, document),
    do: "Сізге № #{document.number} шотын жібереміз."

  defp share_body("kk", :contract, document),
    do: "Сізге № #{document.number} шартын жібереміз."

  defp share_body("kk", :act, document),
    do: "Сізге № #{document.number} актісін жібереміз."

  defp share_body(_locale, :invoice, document),
    do: "Направляем вам счет на оплату № #{document.number}."

  defp share_body(_locale, :contract, document),
    do: "Направляем вам договор № #{document.number}."

  defp share_body(_locale, :act, document),
    do: "Направляем вам акт № #{document.number}."

  defp share_disclaimer("kk"),
    do: "Мессенджер тек ыңғайлы хабарлама арнасы; ресми жіберу арнасы — email."

  defp share_disclaimer(_locale),
    do:
      "Мессенджер используется как удобный канал уведомления; официальный канал отправки — email."

  defp share_url(:whatsapp, text, _public_link) do
    "whatsapp://send?text=#{URI.encode_www_form(text)}"
  end

  defp share_url(:telegram, text, public_link) do
    "https://t.me/share/url?url=#{URI.encode_www_form(public_link)}&text=#{URI.encode_www_form(text)}"
  end

  defp normalize_locale(locale) when is_binary(locale) do
    case String.downcase(String.trim(locale)) do
      "kk" -> "kk"
      _ -> "ru"
    end
  end

  defp normalize_locale(_), do: "ru"
end
