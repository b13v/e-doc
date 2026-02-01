defmodule EdocApi.Errors do
  @moduledoc """
  Standardized error construction and handling across the application.

  Provides consistent error return shapes and canonical error atoms.
  """

  # -------------------------
  # Error Atoms (Canonical)
  # -------------------------

  # Invoice errors
  def invoice_not_found, do: :invoice_not_found
  def invoice_already_issued, do: :invoice_already_issued
  def invoice_not_draft, do: :invoice_not_draft

  # Contract errors
  def contract_not_found, do: :contract_not_found

  # Bank account errors
  def bank_account_required, do: :bank_account_required
  def bank_account_not_found, do: :bank_account_not_found

  # Company errors
  def company_required, do: :company_required
  def company_not_found, do: :company_not_found

  # Validation errors
  def validation_failed, do: :validation_failed
  def items_required, do: :items_required

  # -------------------------
  # Error Constructors
  # -------------------------

  @doc """
  Creates a not found error for a resource type.

  ## Examples

      iex> Errors.not_found(:invoice)
      {:error, :not_found, %{resource: :invoice}}

  """
  def not_found(resource) do
    {:error, :not_found, %{resource: resource}}
  end

  @doc """
  Creates a validation error for a specific field.

  ## Examples

      iex> Errors.validation(:email, "invalid format")
      {:error, :validation, %{field: :email, message: "invalid format"}}

  """
  def validation(field, message) do
    {:error, :validation, %{field: field, message: message}}
  end

  @doc """
  Creates a business rule violation error.

  ## Examples

      iex> Errors.business_rule(:invoice_already_issued, %{status: "issued"})
      {:error, :business_rule, %{rule: :invoice_already_issued, details: %{status: "issued"}}}

  """
  def business_rule(rule, details \\ %{}) do
    {:error, :business_rule, %{rule: rule, details: details}}
  end

  @doc """
  Converts a changeset error to a standardized error format.

  ## Examples

      iex> Errors.from_changeset({:error, changeset})
      {:error, :validation, changeset: changeset}

  """
  def from_changeset({:error, changeset}) when is_struct(changeset, Ecto.Changeset) do
    {:error, :validation, changeset: changeset}
  end

  def from_changeset(other), do: other

  @doc """
  Normalizes an error to a standard shape.
  Ensures we never have nested tuples and converts tuple errors to standard format.

  ## Examples

      iex> Errors.normalize({:error, {:error, :invoice_not_found}})
      {:error, :invoice_not_found}

      iex> Errors.normalize({:error, :some_reason})
      {:error, :some_reason}

      iex> Errors.normalize({:error, {:not_found, %{resource: :contract}}})
      {:error, :not_found, %{resource: :contract}}

  """
  def normalize({:error, {:error, reason}}), do: {:error, reason}
  def normalize({:error, {:error, reason, details}}), do: {:error, reason, details}

  # Handle tuple errors from Repo.rollback: convert to standard 3-tuple format
  def normalize({:error, {:not_found, details}}) when is_map(details),
    do: {:error, :not_found, details}

  def normalize({:error, {:validation, details}}) when is_map(details),
    do: {:error, :validation, details}

  def normalize({:error, {:business_rule, details}}) when is_map(details),
    do: {:error, :business_rule, details}

  def normalize(other), do: other

  # -------------------------
  # Helpers
  # -------------------------

  @doc """
  Checks if an error is a specific type.

  ## Examples

      iex> Errors.error_type?({:error, :invoice_not_found}, :invoice_not_found)
      true

      iex> Errors.error_type?({:error, :other}, :invoice_not_found)
      false

  """
  def error_type?({:error, reason}, expected_reason) when reason == expected_reason,
    do: true

  def error_type?(_, _), do: false

  @doc """
  Checks if an error is a validation error (with changeset).

  ## Examples

      iex> Errors.validation_error?({:error, :validation, changeset: %Ecto.Changeset{}})
      true

      iex> Errors.validation_error?({:error, :invoice_not_found})
      false

  """
  def validation_error?({:error, :validation, opts}) when is_list(opts) do
    Keyword.has_key?(opts, :changeset)
  end

  def validation_error?(_), do: false

  @doc """
  Checks if an error is a business rule violation.

  ## Examples

      iex> Errors.business_rule_error?({:error, :business_rule, rule: :invoice_already_issued})
      true

  """
  def business_rule_error?({:error, :business_rule, _opts}), do: true
  def business_rule_error?(_), do: false
end
