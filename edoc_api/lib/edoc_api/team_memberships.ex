defmodule EdocApi.TeamMemberships do
  import Ecto.Query, warn: false

  alias EdocApi.Accounts.User
  alias EdocApi.Billing
  alias EdocApi.Core.TenantMembership
  alias EdocApi.Repo
  alias EdocApi.Validators.Email

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

  def list_memberships(company_id) when is_binary(company_id) do
    TenantMembership
    |> where(
      [m],
      m.company_id == ^company_id and m.status in ["active", "invited", "pending_seat"]
    )
    |> preload([:user])
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  def active_membership_for_user(company_id, user_id)
      when is_binary(company_id) and is_binary(user_id) do
    TenantMembership
    |> where([m], m.company_id == ^company_id and m.user_id == ^user_id and m.status == "active")
    |> preload([:user])
    |> limit(1)
    |> Repo.one()
  end

  def can_manage_billing_and_team?(company_id, user_id)
      when is_binary(company_id) and is_binary(user_id) do
    case active_membership_for_user(company_id, user_id) do
      %TenantMembership{role: role} when role in ["owner", "admin"] -> true
      _ -> false
    end
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
          if is_nil(membership.user_id) do
            case Repo.delete(membership) do
              {:ok, _deleted} ->
                {:ok,
                 %{
                   mode: :soft_removed_membership,
                   membership_id: membership.id,
                   status: "removed"
                 }}

              {:error, _changeset} ->
                {:error, :reassign_failed}
            end
          else
            case offboarding_owner_user_id(company_id, membership.user_id) do
              nil ->
                {:error, :owner_not_found}

              owner_user_id ->
                case EdocApi.Accounts.offboard_member_from_company(
                       company_id,
                       membership.id,
                       membership.user_id,
                       owner_user_id
                     ) do
                  {:ok, payload} -> {:ok, payload}
                  {:error, reason} -> {:error, reason}
                end
            end
          end
        end
    end
  end

  def accept_pending_memberships_for_user(%User{} = user) do
    normalized_email = Email.normalize(user.email)

    TenantMembership
    |> where(
      [m],
      m.status in ["invited", "pending_seat"] and m.invite_email == ^normalized_email
    )
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Enum.reduce([], fn membership, accepted ->
      case pending_membership_block_reason(membership, user.id) do
        :none ->
          membership
          |> Ecto.Changeset.change(status: "active", user_id: user.id, invite_email: nil)
          |> Repo.update!()

          [membership.id | accepted]

        :seat_limit_reached ->
          if membership.status == "pending_seat" do
            accepted
          else
            membership
            |> Ecto.Changeset.change(status: "pending_seat")
            |> Repo.update!()

            accepted
          end

        :already_active ->
          accepted
      end
    end)
    |> Enum.reverse()
  end

  def active_member_count(company_id) when is_binary(company_id) do
    TenantMembership
    |> where([m], m.company_id == ^company_id and m.status == "active")
    |> Repo.aggregate(:count, :id)
  end

  defp effective_seat_limit(company_id) when is_binary(company_id) do
    case Billing.allowed_user_limit(company_id) do
      {:ok, limit} ->
        limit

      _ ->
        {:ok, subscription} = Billing.ensure_current_subscription_for_company(company_id)
        subscription.plan.included_users
    end
  end

  defp occupied_member_count(company_id) when is_binary(company_id) do
    TenantMembership
    |> where(
      [m],
      m.company_id == ^company_id and m.status in ["active", "invited", "pending_seat"]
    )
    |> Repo.aggregate(:count, :id)
  end

  defp invited_email_exists?(company_id, email) do
    TenantMembership
    |> where(
      [m],
      m.company_id == ^company_id and m.status in ["invited", "pending_seat"] and
        m.invite_email == ^email
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

  defp offboarding_owner_user_id(company_id, excluded_user_id) do
    TenantMembership
    |> where(
      [m],
      m.company_id == ^company_id and m.status == "active" and m.role == "owner" and
        m.user_id != ^excluded_user_id
    )
    |> order_by([m], asc: m.inserted_at)
    |> select([m], m.user_id)
    |> limit(1)
    |> Repo.one()
  end

  defp pending_membership_block_reason(%TenantMembership{} = membership, user_id) do
    cond do
      active_membership_exists?(membership.company_id, user_id) ->
        :already_active

      active_member_count(membership.company_id) >= effective_seat_limit(membership.company_id) ->
        :seat_limit_reached

      true ->
        :none
    end
  end

  defp active_membership_exists?(company_id, user_id) do
    TenantMembership
    |> where(
      [m],
      m.company_id == ^company_id and m.user_id == ^user_id and m.status == "active"
    )
    |> Repo.exists?()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
