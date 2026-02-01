defmodule EdocApiWeb.UnifiedErrorHandler do
  @moduledoc """
  Unified error handling for both HTML and JSON requests.

  Provides consistent error handling across all controller types by dispatching
  based on the request type (HTMX, HTML, or JSON).
  """

  import Plug.Conn
  alias Phoenix.Controller
  alias EdocApiWeb.ErrorMapper

  @doc """
  Handles a result tuple and dispatches to appropriate handlers based on request type.

  ## Options
  - `:success` - Function to call on success: (conn, data) -> conn
  - `:error` - Function to call on error: (conn, type, details) -> conn
  - `:redirect_to` - Default redirect path for HTML errors

  ## Examples

      UnifiedErrorHandler.handle_result(conn, result,
        success: fn conn, _data ->
          redirect(conn, to: "/invoices")
        end,
        error: fn conn, type, details ->
          # Custom error handling
          redirect(conn, to: "/invoices")
        end
      )
  """
  def handle_result(conn, result, opts \\ []) do
    case result do
      {:ok, data} ->
        success_handler = Keyword.get(opts, :success, &default_success_handler/2)
        success_handler.(conn, data)

      {:error, type, details} ->
        error_handler = Keyword.get(opts, :error)

        if error_handler do
          error_handler.(conn, type, details)
        else
          handle_error(conn, type, details, opts)
        end

      {:error, error_atom} when is_atom(error_atom) ->
        handle_error(conn, error_atom, %{}, opts)

      unexpected ->
        handle_error(conn, :internal_error, %{reason: unexpected}, opts)
    end
  end

  @doc """
  Handles an error based on request type (HTMX, HTML, or JSON).
  """
  def handle_error(conn, type, details \\ %{}, opts \\ []) do
    cond do
      htmx_request?(conn) -> handle_htmx_error(conn, type, details, opts)
      json_request?(conn) -> handle_json_error(conn, type, details, opts)
      true -> handle_html_error(conn, type, details, opts)
    end
  end

  # HTMX Error Handling
  defp handle_htmx_error(conn, type, details, _opts) do
    {status, message} = error_to_status_and_message(type, details)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, "<span class='text-red-600'>#{message}</span>")
  end

  # JSON Error Handling
  defp handle_json_error(conn, type, details, _opts) do
    case type do
      :not_found ->
        ErrorMapper.not_found(conn, "#{details[:resource]}_not_found")

      :business_rule ->
        ErrorMapper.unprocessable(conn, to_string(details[:rule]), details[:details])

      :validation ->
        ErrorMapper.validation(conn, details[:changeset])

      _ ->
        ErrorMapper.unprocessable(conn, to_string(type), details)
    end
  end

  # HTML Error Handling
  defp handle_html_error(conn, type, details, opts) do
    message = error_to_message(type, details, opts)
    redirect_path = Keyword.get(opts, :redirect_to, default_redirect_path(conn))

    conn
    |> Controller.put_flash(:error, message)
    |> Controller.redirect(to: redirect_path)
  end

  # Helper functions
  def htmx_request?(conn) do
    conn.assigns[:htmx] && conn.assigns.htmx[:request]
  end

  def json_request?(conn) do
    case get_req_header(conn, "accept") do
      ["application/json" | _] -> true
      _ -> false
    end
  end

  defp error_to_status_and_message(type, details) do
    case type do
      :not_found -> {404, "#{humanize(details[:resource])} not found"}
      :business_rule -> {422, humanize(details[:rule])}
      :validation -> {422, "Validation failed"}
      :cannot_delete_issued_invoice -> {403, "Cannot delete issued invoice"}
      _ -> {500, "An error occurred"}
    end
  end

  defp error_to_message(type, details, opts) do
    Keyword.get(opts, :error_message) ||
      case type do
        :not_found -> "#{humanize(details[:resource])} not found"
        :business_rule -> humanize(details[:rule])
        :cannot_delete_issued_invoice -> "Cannot delete issued invoice"
        _ -> "An error occurred"
      end
  end

  defp default_redirect_path(conn) do
    # Extract base path from current request
    case conn.request_path do
      "/" ->
        "/"

      path ->
        # Get the first segment (e.g., /invoices/123 -> /invoices)
        path |> String.split("/") |> Enum.take(2) |> Enum.join("/")
    end
  end

  defp default_success_handler(conn, _data) do
    conn
  end

  defp humanize(atom) when is_atom(atom) do
    atom
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize(string) when is_binary(string) do
    string
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize(nil), do: ""
end
