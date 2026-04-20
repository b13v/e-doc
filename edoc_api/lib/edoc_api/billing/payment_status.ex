defmodule EdocApi.Billing.PaymentStatus do
  @moduledoc """
  Canonical payment statuses for manual Kaspi confirmation.
  """

  @pending_confirmation "pending_confirmation"
  @confirmed "confirmed"
  @rejected "rejected"

  @all [@pending_confirmation, @confirmed, @rejected]
  @final [@confirmed, @rejected]

  def pending_confirmation, do: @pending_confirmation
  def confirmed, do: @confirmed
  def rejected, do: @rejected

  def all, do: @all
  def valid?(status), do: status in @all
  def final?(status), do: status in @final
end
