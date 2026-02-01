defmodule EdocApiWeb.ErrorMapper do
  import Plug.Conn

  alias EdocApiWeb.Serializers.ErrorSerializer
  alias Phoenix.Controller

  def validation(conn, %Ecto.Changeset{} = changeset, extra \\ %{}) do
    body =
      %{error: "validation_error", details: ErrorSerializer.errors_to_map(changeset)}
      |> Map.merge(extra)

    conn
    |> put_status(:unprocessable_entity)
    |> Controller.json(body)
  end

  def bad_request(conn, code) when is_binary(code) do
    conn
    |> put_status(:bad_request)
    |> Controller.json(%{error: code})
  end

  def not_found(conn, code) when is_binary(code) do
    conn
    |> put_status(:not_found)
    |> Controller.json(%{error: code})
  end

  def already_issued(conn, resource \\ "invoice") when is_binary(resource) do
    conn
    |> put_status(:unprocessable_entity)
    |> Controller.json(%{error: "#{resource}_already_issued"})
  end

  def unauthorized(conn, code \\ "unauthorized") when is_binary(code) do
    conn
    |> put_status(:unauthorized)
    |> Controller.json(%{error: code})
  end

  def unprocessable(conn, code, details \\ nil) when is_binary(code) do
    body =
      case details do
        nil -> %{error: code}
        _ -> %{error: code, details: details}
      end

    conn
    |> put_status(:unprocessable_entity)
    |> Controller.json(body)
  end

  def internal(conn) do
    conn
    |> put_status(:internal_server_error)
    |> Controller.json(%{error: "internal_error"})
  end
end
