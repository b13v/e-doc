defmodule EdocApiWeb.ErrorMapper do
  import Plug.Conn

  alias EdocApiWeb.Serializers.ErrorSerializer
  alias Phoenix.Controller

  def validation(conn, %Ecto.Changeset{} = changeset, extra \\ %{}) do
    body =
      conn
      |> build_body("validation_error", ErrorSerializer.errors_to_map(changeset))
      |> Map.merge(extra)

    conn
    |> put_status(:unprocessable_entity)
    |> Controller.json(body)
  end

  def bad_request(conn, code) when is_binary(code) do
    conn
    |> put_status(:bad_request)
    |> Controller.json(build_body(conn, code))
  end

  def not_found(conn, code) when is_binary(code) do
    conn
    |> put_status(:not_found)
    |> Controller.json(build_body(conn, code))
  end

  def already_issued(conn, resource \\ "invoice") when is_binary(resource) do
    conn
    |> put_status(:unprocessable_entity)
    |> Controller.json(build_body(conn, "#{resource}_already_issued"))
  end

  def unauthorized(conn, code \\ "unauthorized", details \\ nil) when is_binary(code) do
    conn
    |> put_status(:unauthorized)
    |> Controller.json(build_body(conn, code, details))
  end

  def forbidden(conn, code \\ "forbidden", details \\ nil) when is_binary(code) do
    conn
    |> put_status(:forbidden)
    |> Controller.json(build_body(conn, code, details))
  end

  def unprocessable(conn, code, details \\ nil) when is_binary(code) do
    conn
    |> put_status(:unprocessable_entity)
    |> Controller.json(build_body(conn, code, details))
  end

  def too_many_requests(conn, code \\ "rate_limited", details \\ nil) when is_binary(code) do
    conn
    |> put_status(:too_many_requests)
    |> Controller.json(build_body(conn, code, details))
  end

  def internal(conn) do
    conn
    |> put_status(:internal_server_error)
    |> Controller.json(build_body(conn, "internal_error"))
  end

  defp build_body(conn, code, details \\ nil) do
    {message, normalized_details} = extract_message(details)

    %{error: code}
    |> maybe_put(:message, message)
    |> maybe_put(:details, normalized_details)
    |> maybe_put(:request_id, request_id(conn))
  end

  defp extract_message(details) when is_map(details) do
    {message, details} = Map.pop(details, :message)

    case message do
      nil ->
        {string_message, remaining} = Map.pop(details, "message")
        {string_message, normalize_details(remaining)}

      _ ->
        {message, normalize_details(details)}
    end
  end

  defp extract_message(details), do: {nil, details}

  defp normalize_details(%{} = details) when map_size(details) == 0, do: nil
  defp normalize_details(details), do: details

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp request_id(conn) do
    conn.assigns[:request_id] ||
      List.first(get_resp_header(conn, "x-request-id")) ||
      List.first(get_req_header(conn, "x-request-id"))
  end
end
