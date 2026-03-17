defmodule EdocApiWeb.DocumentDeliveryHTMLController do
  use EdocApiWeb, :controller

  plug(:put_view, EdocApiWeb.DocumentDeliveryHTML)

  alias EdocApi.DocumentDelivery
  alias EdocApi.DocumentDelivery.DocumentResolver
  alias EdocApiWeb.DocumentDeliveryUI
  alias EdocApiWeb.UnifiedErrorHandler

  def email_form(conn, %{"type" => type, "id" => id}) do
    user = conn.assigns.current_user

    with {:ok, {document_type, document}} <- DocumentResolver.get_for_user(user.id, type, id) do
      render_email_form(conn, document_type, document, %{}, nil)
    else
      {:error, _reason} ->
        handle_missing_document(conn, type, id)
    end
  end

  def send_email(conn, %{"type" => type, "id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, {document_type, document}} <- DocumentResolver.get_for_user(user.id, type, id) do
      case DocumentDelivery.send_email(user.id, document_type, document.id, params) do
        {:ok, payload} ->
          handle_send_success(conn, document_type, document, payload)

        {:error, :recipient_email_required} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render_email_form(
            document_type,
            document,
            params,
            "Recipient email is required"
          )

        {:error, :email_delivery_failed, _details} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render_email_form(
            document_type,
            document,
            params,
            "Email delivery failed. Please try again."
          )

        {:error, :validation, _details} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render_email_form(
            document_type,
            document,
            params,
            "Recipient email is required"
          )

        {:error, _reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render_email_form(
            document_type,
            document,
            params,
            "Unable to send the document."
          )
      end
    else
      {:error, _reason} ->
        handle_missing_document(conn, type, id)
    end
  end

  def share(conn, %{"type" => type, "id" => id, "channel" => channel} = params) do
    user = conn.assigns.current_user

    case DocumentDelivery.generate_share(
           user.id,
           type,
           id,
           channel,
           Map.put_new(params, "locale", "ru")
         ) do
      {:ok, payload} ->
        if UnifiedErrorHandler.htmx_request?(conn) do
          conn
          |> put_resp_header("hx-redirect", payload.share.share_url)
          |> send_resp(:no_content, "")
        else
          redirect(conn, external: payload.share.share_url)
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Unable to prepare the share link.")
        |> redirect(to: DocumentDeliveryUI.show_path(type, id))
    end
  end

  defp render_email_form(conn, document_type, document, params, error_message) do
    defaults = DocumentDeliveryUI.recipient_defaults(document_type, document)

    render(conn, :email_form,
      page_title: "Send #{DocumentDeliveryUI.document_title(document_type, document)}",
      document_type: document_type,
      document: document,
      document_title: DocumentDeliveryUI.document_title(document_type, document),
      show_path: DocumentDeliveryUI.show_path(document_type, document.id),
      send_email_path: DocumentDeliveryUI.send_email_path(document_type, document.id),
      recipient_name: Map.get(params, "recipient_name") || defaults.recipient_name,
      recipient_email: Map.get(params, "recipient_email") || defaults.recipient_email,
      error_message: error_message
    )
  end

  defp handle_send_success(conn, document_type, document, payload) do
    if UnifiedErrorHandler.htmx_request?(conn) do
      render(conn, :send_success,
        document: document,
        document_title: DocumentDeliveryUI.document_title(document_type, document),
        delivery: payload.delivery,
        public_link: payload.public_link,
        transport: payload.transport
      )
    else
      flash_message =
        case payload.transport do
          %{warning: warning} ->
            "Document sent to #{payload.delivery.recipient_email}. #{warning}"

          _ ->
            "Document sent to #{payload.delivery.recipient_email}."
        end

      conn
      |> put_flash(:info, flash_message)
      |> redirect(to: DocumentDeliveryUI.show_path(document_type, document.id))
    end
  end

  defp handle_missing_document(conn, type, id) do
    if UnifiedErrorHandler.htmx_request?(conn) do
      conn
      |> put_status(:not_found)
      |> put_resp_content_type("text/html")
      |> send_resp(404, "<div class=\"text-red-600\">Document not found.</div>")
    else
      conn
      |> put_flash(:error, "Document not found.")
      |> redirect(to: DocumentDeliveryUI.show_path(type, id))
    end
  end
end
