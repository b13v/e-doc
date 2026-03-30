defmodule EdocApi.InvoiceStatus do
  @moduledoc """
  Centralized module for invoice status constants and helper functions.
  Eliminates hardcoded status strings scattered across the codebase.
  """

  # Status constants
  @status_draft "draft"
  @status_issued "issued"
  @status_paid "paid"
  @status_void "void"

  @all_statuses [@status_draft, @status_issued, @status_paid, @status_void]

  @doc """
  Returns the default status for a new invoice.
  """
  def default, do: @status_draft

  @doc """
  Returns all valid invoice statuses.
  """
  def all, do: @all_statuses

  @doc """
  Returns the draft status constant.
  """
  def draft, do: @status_draft

  @doc """
  Returns the issued status constant.
  """
  def issued, do: @status_issued

  @doc """
  Returns the paid status constant.
  """
  def paid, do: @status_paid

  @doc """
  Returns the void status constant.
  """
  def void, do: @status_void

  @doc """
  Checks if the given status is valid.

  ## Examples

      iex> EdocApi.InvoiceStatus.valid?("draft")
      true

      iex> EdocApi.InvoiceStatus.valid?("invalid")
      false
  """
  def valid?(status), do: status in @all_statuses

  @doc """
  Checks if an invoice is in draft status.

  ## Examples

      iex> EdocApi.InvoiceStatus.is_draft?(%{status: "draft"})
      true

      iex> EdocApi.InvoiceStatus.is_draft?("draft")
      true
  """
  def is_draft?(%{status: status}), do: status == @status_draft
  def is_draft?(status) when is_binary(status), do: status == @status_draft

  @doc """
  Checks if an invoice is in issued status.

  ## Examples

      iex> EdocApi.InvoiceStatus.is_issued?(%{status: "issued"})
      true

      iex> EdocApi.InvoiceStatus.is_issued?("issued")
      true
  """
  def is_issued?(%{status: status}), do: status == @status_issued
  def is_issued?(status) when is_binary(status), do: status == @status_issued

  @doc """
  Checks if an invoice is in paid status.
  """
  def is_paid?(%{status: status}), do: status == @status_paid
  def is_paid?(status) when is_binary(status), do: status == @status_paid

  @doc """
  Checks if an invoice is in void status.
  """
  def is_void?(%{status: status}), do: status == @status_void
  def is_void?(status) when is_binary(status), do: status == @status_void

  @doc """
  Checks if an invoice can be issued (must be in draft status).

  ## Examples

      iex> EdocApi.InvoiceStatus.can_issue?(%{status: "draft"})
      true

      iex> EdocApi.InvoiceStatus.can_issue?(%{status: "issued"})
      false
  """
  def can_issue?(invoice), do: is_draft?(invoice)

  @doc """
  Checks if an invoice is already issued (has issued status or beyond).
  """
  def already_issued?(invoice), do: not is_draft?(invoice)
end
