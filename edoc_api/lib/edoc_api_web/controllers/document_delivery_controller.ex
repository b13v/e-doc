defmodule EdocApiWeb.DocumentDeliveryController do
  use EdocApiWeb, :controller

  alias EdocApi.DocumentDelivery
  alias EdocApiWeb.ErrorMapper
  alias EdocApiWeb.Serializers.DocumentDeliverySerializer

  def send_email(conn, %{"type" => type, "id" => id} = params) do
    user = conn.assigns.current_user

    case DocumentDelivery.send_email(user.id, type, id, params) do
      {:ok, payload} ->
        json(conn, %{
          delivery: DocumentDeliverySerializer.to_map(payload.delivery),
          public_link: payload.public_link,
          document: payload.document,
          transport: payload.transport
        })

      {:error, :document_not_found} ->
        ErrorMapper.not_found(conn, "document_not_found")

      {:error, :unsupported_document_type} ->
        ErrorMapper.unprocessable(conn, "unsupported_document_type")

      {:error, :recipient_email_required} ->
        ErrorMapper.unprocessable(conn, "recipient_email_required")

      {:error, :email_delivery_failed, details} ->
        ErrorMapper.unprocessable(conn, "email_delivery_failed", details)

      {:error, :validation, %{changeset: changeset}} ->
        ErrorMapper.validation(conn, changeset)
    end
  end

  def share(conn, %{"type" => type, "id" => id, "channel" => channel} = params) do
    user = conn.assigns.current_user

    case DocumentDelivery.generate_share(user.id, type, id, channel, params) do
      {:ok, payload} ->
        json(conn, %{
          delivery: DocumentDeliverySerializer.to_map(payload.delivery),
          public_link: payload.public_link,
          share: payload.share,
          document: payload.document
        })

      {:error, :document_not_found} ->
        ErrorMapper.not_found(conn, "document_not_found")

      {:error, :unsupported_document_type} ->
        ErrorMapper.unprocessable(conn, "unsupported_document_type")

      {:error, :unsupported_share_channel} ->
        ErrorMapper.unprocessable(conn, "unsupported_share_channel")

      {:error, :validation, %{changeset: changeset}} ->
        ErrorMapper.validation(conn, changeset)
    end
  end
end
