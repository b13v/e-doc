defmodule EdocApiWeb.ControllerHelpers do
  @moduledoc """
  Unified error handling helpers for controllers.

  Provides consistent patterns for handling context function results,
  with proper logging of unexpected errors.

  Supports standardized error formats:
  - {:error, :not_found, %{resource: atom}}
  - {:error, :validation, %{changeset: %Ecto.Changeset{}}}
  - {:error, :business_rule, %{rule: atom, details: map}}
  """

  require Logger
  alias EdocApiWeb.ErrorMapper

  @doc """
  Handles the result of a context function call with a success callback.

  ## Examples

      handle_result(conn, result, fn conn, data ->
        conn |> put_status(:created) |> json(%{invoice: serialize(data)})
      end)

  The error_map parameter allows mapping specific error atoms to handler functions:

      handle_result(conn, result, success_fn, %{
        items_required: &ErrorMapper.unprocessable(&1, "items_required"),
        not_found: &ErrorMapper.not_found(&1, "resource_not_found")
      })
  """
  def handle_result(conn, result, success_callback, error_map \\ %{}) do
    case result do
      {:ok, data} ->
        success_callback.(conn, data)

      # Legacy format: Ecto.Changeset errors
      {:error, %Ecto.Changeset{} = changeset} ->
        ErrorMapper.validation(conn, changeset)

      # Standardized format: {:error, type, details}
      {:error, :not_found, %{resource: resource}} ->
        ErrorMapper.not_found(conn, "#{resource}_not_found")

      {:error, :validation, %{changeset: changeset}} ->
        ErrorMapper.validation(conn, changeset)

      {:error, :business_rule, %{rule: rule} = details} ->
        handle_business_rule_error(conn, rule, details, error_map)

      # Legacy format: simple atom errors (for backwards compatibility)
      {:error, error_atom} when is_atom(error_atom) ->
        case Map.fetch(error_map, error_atom) do
          {:ok, handler} when is_function(handler, 1) ->
            handler.(conn)

          {:ok, {module, function, args}} ->
            apply(module, function, [conn | args])

          :error ->
            Logger.warning("Unhandled error atom in controller: #{inspect(error_atom)}")
            ErrorMapper.internal(conn)
        end

      # Legacy format: atom with details (for backwards compatibility)
      {:error, error_atom, details} when is_atom(error_atom) and is_map(details) ->
        case Map.fetch(error_map, error_atom) do
          {:ok, handler} when is_function(handler, 2) ->
            handler.(conn, details)

          {:ok, {module, function, args}} ->
            apply(module, function, [conn, details | args])

          :error ->
            Logger.warning("Unhandled error with details: #{inspect({error_atom, details})}")
            ErrorMapper.internal(conn)
        end

      {:error, unexpected} ->
        Logger.error("Unexpected error in controller: #{inspect(unexpected)}")
        ErrorMapper.internal(conn)

      other ->
        Logger.error("Unexpected result format in controller: #{inspect(other)}")
        ErrorMapper.internal(conn)
    end
  end

  # Handle business rule errors with specific mappings
  defp handle_business_rule_error(conn, rule, details, error_map) do
    case rule do
      :invalid_credentials ->
        ErrorMapper.unauthorized(conn, "Invalid credentials")

      :company_required ->
        ErrorMapper.unprocessable(conn, "company_required")

      :contract_not_editable ->
        ErrorMapper.unprocessable(conn, "contract_not_editable", details)

      :contract_already_issued ->
        ErrorMapper.already_issued(conn, "contract")

      :buyer_required ->
        ErrorMapper.unprocessable(conn, "buyer_required", details)

      _ ->
        # Check if there's a custom handler in error_map
        case Map.fetch(error_map, rule) do
          {:ok, handler} when is_function(handler, 1) ->
            handler.(conn)

          {:ok, handler} when is_function(handler, 2) ->
            handler.(conn, details)

          :error ->
            Logger.warning("Unhandled business rule: #{inspect(rule)}")
            ErrorMapper.unprocessable(conn, to_string(rule), details)
        end
    end
  end

  @doc """
  Convenience wrapper for handle_result with common error mappings.

  Automatically handles these common errors:
  - :not_found -> 404
  - :company_required -> 422
  - :items_required -> 422
  - :bank_account_not_found -> 422
  - :bank_account_required -> 422
  - :already_issued -> 422

  Additional error mappings can be provided via the error_map parameter.
  """
  def handle_common_result(conn, result, success_callback, extra_error_map \\ %{}) do
    common_errors = %{
      not_found: &ErrorMapper.not_found(&1, "not_found"),
      company_required: &ErrorMapper.unprocessable(&1, "company_required"),
      items_required: &ErrorMapper.unprocessable(&1, "items_required"),
      bank_account_not_found: &ErrorMapper.unprocessable(&1, "bank_account_not_found"),
      bank_account_required: &ErrorMapper.unprocessable(&1, "bank_account_required"),
      invoice_already_issued: &ErrorMapper.already_issued/1,
      invoice_not_found: &ErrorMapper.not_found(&1, "invoice_not_found"),
      cannot_issue: fn conn, details ->
        ErrorMapper.unprocessable(conn, "cannot_issue", details)
      end
    }

    error_map = Map.merge(common_errors, extra_error_map)
    handle_result(conn, result, success_callback, error_map)
  end
end
