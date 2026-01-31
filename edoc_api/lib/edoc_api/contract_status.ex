defmodule EdocApi.ContractStatus do
  @moduledoc """
  Centralized module for contract status constants and helper functions.

  Statuses follow the contract lifecycle:
  - draft: Initial state, contract is being prepared
  - issued: Contract has been issued/finalized, cannot be modified
  - signed: Contract has been signed by both parties (future extension)

  Invoices may only be issued from contracts with status "issued" or "signed".
  """

  @status_draft "draft"
  @status_issued "issued"
  @status_signed "signed"

  @all_statuses [@status_draft, @status_issued, @status_signed]

  def default, do: @status_draft
  def all, do: @all_statuses
  def draft, do: @status_draft
  def issued, do: @status_issued
  def signed, do: @status_signed

  def valid?(status), do: status in @all_statuses

  def is_draft?(%{status: status}), do: status == @status_draft
  def is_draft?(status) when is_binary(status), do: status == @status_draft

  def is_issued?(%{status: status}), do: status == @status_issued
  def is_issued?(status) when is_binary(status), do: status == @status_issued

  def is_signed?(%{status: status}), do: status == @status_signed
  def is_signed?(status) when is_binary(status), do: status == @status_signed

  # A contract can be issued if it's in draft status
  def can_issue?(contract), do: is_draft?(contract)
  def already_issued?(contract), do: not is_draft?(contract)

  # A contract can be modified only in draft status
  def can_edit?(%{status: status}), do: status == @status_draft
  def can_edit?(status) when is_binary(status), do: status == @status_draft

  # Invoices can be issued from contracts that are issued or signed
  def can_invoice_from?(%{status: status}), do: status in [@status_issued, @status_signed]

  def can_invoice_from?(status) when is_binary(status),
    do: status in [@status_issued, @status_signed]
end
