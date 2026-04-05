defmodule EdocApiWeb.CompanyController do
  use EdocApiWeb, :controller

  alias EdocApi.Companies
  alias EdocApi.Monetization
  alias EdocApiWeb.ErrorMapper
  alias EdocApiWeb.Serializers.CompanySerializer

  def show(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        ErrorMapper.not_found(conn, "company_not_found")

      company ->
        json(conn, %{company: CompanySerializer.to_map(company)})
    end
  end

  def upsert(conn, params) do
    user = conn.assigns.current_user

    # case Core.upsert_company_for_user(user.id, params) do
    #   {:ok, company} ->
    #     json(conn, %{company: company_json(company)})

    #   {:error, %Ecto.Changeset{} = changeset} ->
    #     conn
    #     |> put_status(:unprocessable_entity)
    #     |> json(%{error: "validation_error", details: errors_to_map(changeset)})
    # end
    case Companies.upsert_company_for_user(user.id, params) do
      {:ok, company, warnings} ->
        json(conn, %{company: CompanySerializer.to_map(company), warnings: warnings})

      {:error, %Ecto.Changeset{} = changeset, warnings} ->
        ErrorMapper.validation(conn, changeset, %{warnings: warnings})
    end
  end

  def update_subscription(conn, params) do
    user = conn.assigns.current_user
    subscription_params = Map.get(params, "subscription", params)
    plan = Map.get(subscription_params, "plan", "starter")

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        ErrorMapper.unprocessable(conn, "company_required")

      company ->
        attrs = %{
          "plan" => plan,
          "skip_trial" => true
        }

        case Monetization.validate_plan_change(company.id, plan) do
          {:ok, _details} ->
            case Monetization.activate_subscription_for_company(company.id, attrs) do
              {:ok, _subscription} ->
                json(conn, %{subscription: Monetization.subscription_snapshot(company.id)})

              {:error, :validation, %{changeset: changeset}} ->
                ErrorMapper.validation(conn, changeset)

              {:error, _reason} ->
                ErrorMapper.unprocessable(conn, "subscription_update_failed")
            end

          {:error, :seat_limit_exceeded_on_downgrade, details} ->
            ErrorMapper.unprocessable(
              conn,
              "seat_limit_exceeded_on_downgrade",
              downgrade_details_to_json(details)
            )
        end
    end
  end

  defp downgrade_details_to_json(details) do
    %{
      plan: details.plan,
      seat_limit: details.seat_limit,
      seats_used: details.seats_used,
      seats_to_remove: details.seats_to_remove,
      blocking_memberships:
        Enum.map(details.blocking_memberships, fn membership ->
          %{
            id: membership.id,
            status: membership.status,
            role: membership.role,
            email: membership.invite_email || (membership.user && membership.user.email)
          }
        end)
    }
  end
end
