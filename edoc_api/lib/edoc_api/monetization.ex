defmodule EdocApi.Monetization do
  @moduledoc false

  alias EdocApi.Billing
  alias EdocApi.Core.TenantMembership
  alias EdocApi.TeamMemberships

  def activate_subscription_for_company(company_id, attrs) when is_binary(company_id) do
    plan = Map.get(attrs, "plan") || Map.get(attrs, :plan) || "starter"

    opts =
      []
      |> put_opt(:period_start, Map.get(attrs, "period_start") || Map.get(attrs, :period_start))
      |> put_opt(:period_end, Map.get(attrs, "period_end") || Map.get(attrs, :period_end))

    with {:ok, subscription} <- Billing.ensure_current_subscription_for_company(company_id),
         {:ok, subscription} <- Billing.activate_subscription(subscription, plan, opts) do
      {:ok, subscription}
    end
  end

  defdelegate ensure_owner_membership(company_id, user_id), to: TeamMemberships
  defdelegate list_memberships(company_id), to: TeamMemberships
  defdelegate active_membership_for_user(company_id, user_id), to: TeamMemberships
  defdelegate can_manage_billing_and_team?(company_id, user_id), to: TeamMemberships
  defdelegate invite_member(company_id, attrs), to: TeamMemberships
  defdelegate remove_membership(company_id, membership_id), to: TeamMemberships
  defdelegate accept_pending_memberships_for_user(user), to: TeamMemberships
  defdelegate active_member_count(company_id), to: TeamMemberships

  def subscription_snapshot(company_id) when is_binary(company_id) do
    billing = Billing.tenant_billing_snapshot(company_id)
    subscription = billing.subscription || %{}

    %{
      plan: billing.current_plan_code || "trial",
      status: Map.get(subscription, :status) || "trialing",
      period_start:
        Map.get(subscription, :current_period_start) || Map.get(subscription, :period_start),
      period_end:
        Map.get(subscription, :current_period_end) || Map.get(subscription, :period_end),
      documents_used: billing.used_documents || 0,
      document_limit: billing.current_document_limit || 0,
      documents_remaining:
        max((billing.current_document_limit || 0) - (billing.used_documents || 0), 0),
      seats_used: billing.used_seats || 0,
      seat_limit: billing.current_seat_limit || 0
    }
  end

  def effective_seat_limit(company_id) when is_binary(company_id) do
    {:ok, limit} = Billing.allowed_user_limit(company_id)
    limit
  end

  def can_activate_member?(company_id) when is_binary(company_id) do
    case Billing.ensure_can_add_user(company_id) do
      {:ok, _details} -> true
      _ -> false
    end
  end

  def validate_plan_change(company_id, target_plan)
      when is_binary(company_id) and is_binary(target_plan) do
    with {:ok, target} <- Billing.get_plan_by_code(target_plan),
         {:ok, _subscription} <- Billing.ensure_current_subscription_for_company(company_id) do
      seats_used = occupied_member_count(company_id)
      seat_limit = target.included_users

      if seats_used > seat_limit do
        {:error, :seat_limit_exceeded_on_downgrade,
         %{
           plan: target.code,
           seat_limit: seat_limit,
           seats_used: seats_used,
           seats_to_remove: seats_used - seat_limit,
           blocking_memberships: blocking_memberships_for_downgrade(company_id, seat_limit)
         }}
      else
        {:ok, %{plan: target.code, seat_limit: seat_limit, seats_used: seats_used}}
      end
    end
  end

  def consume_document_quota(company_id, document_type, document_id, _event_type)
      when is_binary(company_id) and is_binary(document_type) and is_binary(document_id) do
    case Billing.record_document_usage(company_id, document_type, document_id) do
      {:ok, _event} ->
        usage_details(company_id)

      {:error, reason, details} when reason in [:quota_exceeded, :subscription_restricted] ->
        {:error, :quota_exceeded, maybe_put_reason(details, reason)}

      other ->
        other
    end
  end

  def ensure_document_creation_allowed(company_id) when is_binary(company_id) do
    case Billing.ensure_can_create_document(company_id) do
      {:ok, details} ->
        {:ok, details}

      {:error, reason, details} when reason in [:quota_exceeded, :subscription_restricted] ->
        {:error, :quota_exceeded, maybe_put_reason(details, reason)}

      other ->
        other
    end
  end

  defp usage_details(company_id) do
    {:ok, used} = Billing.current_document_usage(company_id)
    {:ok, limit} = Billing.allowed_document_limit(company_id)
    {:ok, %{used: used, limit: limit, remaining: max(limit - used, 0)}}
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_reason(details, :subscription_restricted),
    do: Map.put(details, :reason, :subscription_restricted)

  defp maybe_put_reason(details, _reason), do: details

  defp occupied_member_count(company_id) do
    TeamMemberships.list_memberships(company_id)
    |> length()
  end

  defp blocking_memberships_for_downgrade(company_id, seat_limit) do
    overflow = max(occupied_member_count(company_id) - seat_limit, 0)

    TeamMemberships.list_memberships(company_id)
    |> Enum.reject(&last_owner?/1)
    |> Enum.sort_by(&downgrade_priority/1)
    |> Enum.take(overflow)
  end

  defp last_owner?(%TenantMembership{status: "active", role: "owner"} = membership) do
    TeamMemberships.list_memberships(membership.company_id)
    |> Enum.count(&(&1.status == "active" and &1.role == "owner")) == 1
  end

  defp last_owner?(_membership), do: false

  defp downgrade_priority(%TenantMembership{status: "invited"}), do: {0, 0}
  defp downgrade_priority(%TenantMembership{status: "pending_seat"}), do: {0, 0}
  defp downgrade_priority(%TenantMembership{status: "active", role: "member"}), do: {1, 0}
  defp downgrade_priority(%TenantMembership{status: "active", role: "admin"}), do: {2, 0}
  defp downgrade_priority(%TenantMembership{status: "active", role: "owner"}), do: {3, 0}
  defp downgrade_priority(_membership), do: {4, 0}
end
