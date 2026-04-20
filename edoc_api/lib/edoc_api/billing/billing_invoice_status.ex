defmodule EdocApi.Billing.BillingInvoiceStatus do
  @moduledoc """
  Canonical billing invoice statuses.

  Billing invoices represent what the tenant must pay for a subscription period.
  They are intentionally separate from tenant document invoices.
  """

  @draft "draft"
  @sent "sent"
  @paid "paid"
  @overdue "overdue"
  @canceled "canceled"

  @all [@draft, @sent, @paid, @overdue, @canceled]
  @payable [@sent, @overdue]

  def draft, do: @draft
  def sent, do: @sent
  def paid, do: @paid
  def overdue, do: @overdue
  def canceled, do: @canceled

  def all, do: @all
  def valid?(status), do: status in @all
  def payable?(status), do: status in @payable
end
