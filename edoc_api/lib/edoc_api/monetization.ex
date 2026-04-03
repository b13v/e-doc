defmodule EdocApi.Monetization do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Accounts.User
  alias EdocApi.Core.TenantMembership
  alias EdocApi.Core.TenantSubscription
  alias EdocApi.Core.TenantUsageEvent
  alias EdocApi.Validators.Email

  @trial_document_limit 10
  @trial_included_seat_limit 2

  @plan_defaults %{
    "trial" => %{documents: 10, seats: 2},
    "starter" => %{documents: 50, seats: 2},
    "basic" => %{documents: 500, seats: 5}
  }

  def activate_subscription_for_company(company_id, attrs) when is_binary(company_id) do
    plan = normalize_plan(Map.get(attrs, "plan") || Map.get(attrs, :plan) || "starter")
    now = now()
    period_start = Map.get(attrs, "period_start") || Map.get(attrs, :period_start) || now
    period_end = Map.get(attrs, "period_end") || Map.get(attrs, :period_end) || add_days(period_start, 30)
    skip_trial = truthy?(Map.get(attrs, "skip_trial") || Map.get(attrs, :skip_trial))

    defaults = Map.fetch!(@plan_defaults, plan)

    included_document_limit =
      Map.get(attrs, "included_document_limit") ||
        Map.get(attrs, :included_document_limit) ||
        defaults.documents

    included_seat_limit =
      Map.get(attrs, "included_seat_limit") ||
        Map.get(attrs, :included_seat_limit) ||
        defaults.seats

    add_on_seat_quantity =
      Map.get(attrs, "add_on_seat_quantity") || Map.get(attrs, :add_on_seat_quantity) || 0

    Repo.transaction(fn ->
      from(s in TenantSubscription,
        where: s.company_id == ^company_id and s.status == "active"
      )
      |> Repo.update_all(set: [status: "canceled", updated_at: now])

      subscription_attrs = %{
        company_id: company_id,
        plan: plan,
        status: "active",
        period_start: period_start,
        period_end: period_end,
        included_document_limit: included_document_limit,
        included_seat_limit: included_seat_limit,
        add_on_seat_quantity: add_on_seat_quantity,
        trial_document_limit: @trial_document_limit,
        trial_started_at: if(plan == "trial", do: now),
        trial_ended_at: nil,
        skip_trial: skip_trial
      }

      %TenantSubscription{}
      |> TenantSubscription.changeset(subscription_attrs)
      |> Repo.insert()
    end)
    |> case do
      {:ok, {:ok, subscription}} -> {:ok, subscription}
      {:ok, {:error, changeset}} -> {:error, :validation, %{changeset: changeset}}
      {:error, {:error, changeset}} -> {:error, :validation, %{changeset: changeset}}
      {:error, reason} -> {:error, reason}
    end
  end

  def ensure_owner_membership(company_id, user_id)
      when is_binary(company_id) and is_binary(user_id) do
    attrs = %{company_id: company_id, user_id: user_id, role: "owner", status: "active"}

    %TenantMembership{}
    |> TenantMembership.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [role: "owner", status: "active", updated_at: now()]],
      conflict_target: [:company_id, :user_id]
    )
  end

  def effective_seat_limit(company_id) when is_binary(company_id) do
    subscription = get_or_create_active_subscription!(company_id)
    max(subscription.included_seat_limit + subscription.add_on_seat_quantity, 1)
  end

  def list_memberships(company_id) when is_binary(company_id) do
    TenantMembership
    |> where([m], m.company_id == ^company_id and m.status in ["active", "invited"])
    |> preload([:user])
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  def invite_member(company_id, attrs) when is_binary(company_id) and is_map(attrs) do
    email = attrs |> Map.get("email") |> Email.normalize()
    role = Map.get(attrs, "role", "member")

    cond do
      role not in ["admin", "member"] ->
        {:error, :invalid_role}

      invited_email_exists?(company_id, email) ->
        {:error, :duplicate_invite, %{email: email}}

      active_member_email_exists?(company_id, email) ->
        {:error, :duplicate_member, %{email: email}}

      occupied_member_count(company_id) >= effective_seat_limit(company_id) ->
        {:error, :seat_limit_reached, %{limit: effective_seat_limit(company_id)}}

      true ->
        %TenantMembership{}
        |> TenantMembership.changeset(%{
          company_id: company_id,
          invite_email: email,
          role: role,
          status: "invited"
        })
        |> Repo.insert()
    end
  end

  def remove_membership(company_id, membership_id)
      when is_binary(company_id) and is_binary(membership_id) do
    case Repo.get_by(TenantMembership, id: membership_id, company_id: company_id) do
      nil ->
        {:error, :not_found}

      %TenantMembership{} = membership ->
        if last_owner?(membership) do
          {:error, :last_owner}
        else
          membership
          |> Ecto.Changeset.change(status: "removed", invite_email: nil, user_id: nil)
          |> Repo.update()
        end
    end
  end

  def accept_pending_memberships_for_user(%User{} = user) do
    normalized_email = Email.normalize(user.email)

    TenantMembership
    |> where(
      [m],
      m.status == "invited" and m.invite_email == ^normalized_email
    )
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Enum.reduce([], fn membership, accepted ->
      if can_activate_pending_membership?(membership, user.id) do
        membership
        |> Ecto.Changeset.change(status: "active", user_id: user.id, invite_email: nil)
        |> Repo.update!()

        [membership.id | accepted]
      else
        accepted
      end
    end)
    |> Enum.reverse()
  end

  def subscription_snapshot(company_id) when is_binary(company_id) do
    subscription = get_or_create_active_subscription!(company_id) |> roll_paid_period_if_needed()
    seats_used = occupied_member_count(company_id)
    seat_limit = effective_seat_limit(company_id)
    documents_used = usage_count(subscription)
    document_limit = document_limit(subscription)

    %{
      plan: subscription.plan,
      status: subscription.status,
      period_start: subscription.period_start,
      period_end: subscription.period_end,
      documents_used: documents_used,
      document_limit: document_limit,
      documents_remaining: max(document_limit - documents_used, 0),
      seats_used: seats_used,
      seat_limit: seat_limit,
      add_on_seat_quantity: subscription.add_on_seat_quantity
    }
  end

  def active_member_count(company_id) when is_binary(company_id) do
    TenantMembership
    |> where([m], m.company_id == ^company_id and m.status == "active")
    |> Repo.aggregate(:count, :id)
  end

  def can_activate_member?(company_id) when is_binary(company_id) do
    active = active_member_count(company_id)
    limit = effective_seat_limit(company_id)
    active < limit
  end

  defp occupied_member_count(company_id) when is_binary(company_id) do
    TenantMembership
    |> where([m], m.company_id == ^company_id and m.status in ["active", "invited"])
    |> Repo.aggregate(:count, :id)
  end

  defp invited_email_exists?(company_id, email) do
    TenantMembership
    |> where(
      [m],
      m.company_id == ^company_id and m.status == "invited" and m.invite_email == ^email
    )
    |> Repo.exists?()
  end

  defp active_member_email_exists?(company_id, email) do
    TenantMembership
    |> where([m], m.company_id == ^company_id and m.status == "active")
    |> join(:inner, [m], u in assoc(m, :user))
    |> where([_m, u], u.email == ^email)
    |> Repo.exists?()
  end

  defp last_owner?(%TenantMembership{status: "active", role: "owner"} = membership) do
    TenantMembership
    |> where(
      [m],
      m.company_id == ^membership.company_id and m.status == "active" and m.role == "owner"
    )
    |> Repo.aggregate(:count, :id) == 1
  end

  defp last_owner?(_membership), do: false

  defp can_activate_pending_membership?(%TenantMembership{} = membership, user_id) do
    not active_membership_exists?(membership.company_id, user_id) and
      active_member_count(membership.company_id) < effective_seat_limit(membership.company_id)
  end

  defp active_membership_exists?(company_id, user_id) do
    TenantMembership
    |> where(
      [m],
      m.company_id == ^company_id and m.user_id == ^user_id and m.status == "active"
    )
    |> Repo.exists?()
  end

  def consume_document_quota(company_id, document_type, document_id, event_type)
      when is_binary(company_id) and is_binary(document_type) and is_binary(document_id) and
             is_binary(event_type) do
    subscription = get_or_create_active_subscription!(company_id) |> roll_paid_period_if_needed()
    now = now()
    limit = document_limit(subscription)

    insert_result =
      %TenantUsageEvent{}
      |> TenantUsageEvent.changeset(%{
        company_id: company_id,
        event_type: event_type,
        document_type: document_type,
        document_id: document_id,
        occurred_at: now,
        period_start: subscription.period_start,
        period_end: subscription.period_end
      })
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:company_id, :document_type, :document_id]
      )

    case insert_result do
      {:ok, _event} ->
        used = usage_count(subscription)

        if used > limit do
          {:error, :quota_exceeded,
           %{
             company_id: company_id,
             plan: subscription.plan,
             used: used - 1,
             limit: limit,
             period_end: subscription.period_end
           }}
        else
          {:ok, %{used: used, limit: limit, remaining: max(limit - used, 0)}}
        end

      {:error, _changeset} ->
        {:ok, %{duplicate: true}}
    end
  end

  defp get_or_create_active_subscription!(company_id) do
    case active_subscription(company_id) do
      nil ->
        trial_start = now()

        %TenantSubscription{}
        |> TenantSubscription.changeset(%{
          company_id: company_id,
          plan: "trial",
          status: "active",
          period_start: trial_start,
          period_end: add_days(trial_start, 3650),
          included_document_limit: @trial_document_limit,
          included_seat_limit: @trial_included_seat_limit,
          add_on_seat_quantity: 0,
          trial_document_limit: @trial_document_limit,
          trial_started_at: trial_start,
          trial_ended_at: nil,
          skip_trial: false
        })
        |> Repo.insert!()

      subscription ->
        subscription
    end
  end

  defp active_subscription(company_id) do
    TenantSubscription
    |> where([s], s.company_id == ^company_id and s.status == "active")
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp roll_paid_period_if_needed(%TenantSubscription{plan: "trial"} = subscription), do: subscription

  defp roll_paid_period_if_needed(%TenantSubscription{} = subscription) do
    now = now()

    if DateTime.compare(now, subscription.period_end) == :lt do
      subscription
    else
      next_start = subscription.period_end
      next_end = add_days(next_start, 30)

      subscription
      |> Ecto.Changeset.change(period_start: next_start, period_end: next_end)
      |> Repo.update!()
    end
  end

  defp usage_count(%TenantSubscription{plan: "trial", company_id: company_id}) do
    TenantUsageEvent
    |> where([u], u.company_id == ^company_id)
    |> Repo.aggregate(:count, :id)
  end

  defp usage_count(%TenantSubscription{} = subscription) do
    TenantUsageEvent
    |> where(
      [u],
      u.company_id == ^subscription.company_id and
        u.occurred_at >= ^subscription.period_start and
        u.occurred_at < ^subscription.period_end
    )
    |> Repo.aggregate(:count, :id)
  end

  defp document_limit(%TenantSubscription{plan: "trial", trial_document_limit: trial_limit}),
    do: trial_limit

  defp document_limit(%TenantSubscription{included_document_limit: limit}), do: limit

  defp normalize_plan(plan) when plan in ["trial", "starter", "basic"], do: plan
  defp normalize_plan(_), do: "starter"

  defp add_days(%DateTime{} = datetime, days), do: DateTime.add(datetime, days * 86_400, :second)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_), do: false
end
