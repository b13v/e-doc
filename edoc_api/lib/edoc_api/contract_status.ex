defmodule EdocApi.ContractStatus do
  @moduledoc """
  Centralized module for contract status constants and helper functions.
  """

  @status_draft "draft"
  @status_issued "issued"

  @all_statuses [@status_draft, @status_issued]

  def default, do: @status_draft
  def all, do: @all_statuses
  def draft, do: @status_draft
  def issued, do: @status_issued

  def valid?(status), do: status in @all_statuses

  def is_draft?(%{status: status}), do: status == @status_draft
  def is_draft?(status) when is_binary(status), do: status == @status_draft

  def is_issued?(%{status: status}), do: status == @status_issued
  def is_issued?(status) when is_binary(status), do: status == @status_issued

  def can_issue?(contract), do: is_draft?(contract)
  def already_issued?(contract), do: not is_draft?(contract)
end
