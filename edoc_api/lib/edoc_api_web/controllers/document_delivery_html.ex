defmodule EdocApiWeb.DocumentDeliveryHTML do
  use EdocApiWeb, :html

  def localized_transport_warning(nil), do: nil

  def localized_transport_warning(
        "SMTP is not configured. This email was captured by the local mailer adapter and was not delivered to the recipient inbox."
      ) do
    gettext(
      "SMTP is not configured. This email was captured by the local mailer adapter and was not delivered to the recipient inbox."
    )
  end

  def localized_transport_warning(warning), do: warning

  embed_templates("document_delivery_html/*")
end
