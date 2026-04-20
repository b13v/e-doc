defmodule EdocApi.Billing.SubscriptionStatus do
  @moduledoc """
  Canonical subscription lifecycle statuses for billing.
  """

  @trialing "trialing"
  @active "active"
  @grace_period "grace_period"
  @past_due "past_due"
  @suspended "suspended"
  @canceled "canceled"

  @all [@trialing, @active, @grace_period, @past_due, @suspended, @canceled]
  @good_standing [@trialing, @active, @grace_period]
  @restricted [@past_due, @suspended, @canceled]

  def trialing, do: @trialing
  def active, do: @active
  def grace_period, do: @grace_period
  def past_due, do: @past_due
  def suspended, do: @suspended
  def canceled, do: @canceled

  def all, do: @all
  def valid?(status), do: status in @all
  def good_standing?(status), do: status in @good_standing
  def restricted?(status), do: status in @restricted
end
