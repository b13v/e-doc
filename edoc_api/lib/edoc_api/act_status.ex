defmodule EdocApi.ActStatus do
  @moduledoc """
  Centralized module for act status constants and helper functions.
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

  def is_draft?(%{status: status}), do: status == @status_draft
  def is_draft?(status) when is_binary(status), do: status == @status_draft

  def is_issued?(%{status: status}), do: status == @status_issued
  def is_issued?(status) when is_binary(status), do: status == @status_issued

  def is_signed?(%{status: status}), do: status == @status_signed
  def is_signed?(status) when is_binary(status), do: status == @status_signed

  def can_issue?(act), do: is_draft?(act)
  def already_issued?(act), do: not is_draft?(act)

  def can_sign?(act), do: is_issued?(act)
  def already_signed?(act), do: is_signed?(act)
end
