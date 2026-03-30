defmodule EdocApiWeb.PublicDocumentController do
  use EdocApiWeb, :controller

  alias EdocApi.DocumentDelivery

  plug(:put_layout, false)

  def show(conn, %{"token" => token}) do
    case DocumentDelivery.open_public_document(token) do
      {:ok, public_document} ->
        render(conn, :show, public_document: public_document)

      {:error, :public_token_not_found} ->
        send_resp(conn, :not_found, "Not found")
    end
  end

  def pdf(conn, %{"token" => token}) do
    case DocumentDelivery.get_public_document_pdf(token) do
      {:ok, payload} ->
        conn
        |> put_resp_header("cache-control", "private, no-store, max-age=0")
        |> put_resp_header("pragma", "no-cache")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(inline; filename="#{payload.filename}"))
        |> send_resp(200, payload.pdf_binary)

      {:error, :public_token_not_found} ->
        send_resp(conn, :not_found, "Not found")
    end
  end
end
