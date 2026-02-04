defmodule EdocApiWeb.BuyersController do
  use EdocApiWeb, :controller

  alias EdocApi.Buyers
  alias EdocApi.Companies
  alias EdocApi.Core.Buyer
  alias EdocApiWeb.ErrorMapper

  action_fallback(EdocApiWeb.FallbackController)

  def index(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        json(conn, %{buyers: []})

      company ->
        buyers = Buyers.list_buyers_for_company(company.id)
        render(conn, :index, buyers: buyers)
    end
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        ErrorMapper.not_found(conn, "company_not_found")

      company ->
        case Buyers.get_buyer_for_company(id, company.id) do
          nil ->
            ErrorMapper.not_found(conn, "buyer_not_found")

          buyer ->
            render(conn, :show, buyer: buyer)
        end
    end
  end

  def create(conn, %{"buyer" => buyer_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        ErrorMapper.not_found(conn, "company_not_found")

      company ->
        case Buyers.create_buyer_for_company(company.id, buyer_params) do
          {:ok, buyer} ->
            conn
            |> put_status(:created)
            |> render(:show, buyer: buyer)

          {:error, %Ecto.Changeset{} = changeset} ->
            ErrorMapper.validation(conn, changeset)

          {:error, reason} ->
            ErrorMapper.unprocessable(conn, "buyer_creation_failed", %{reason: inspect(reason)})
        end
    end
  end

  def update(conn, %{"id" => id, "buyer" => buyer_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        ErrorMapper.not_found(conn, "company_not_found")

      company ->
        case Buyers.update_buyer(id, buyer_params, company.id) do
          {:ok, buyer} ->
            render(conn, :show, buyer: buyer)

          {:error, %Ecto.Changeset{} = changeset} ->
            ErrorMapper.validation(conn, changeset)

          {:error, :not_found} ->
            ErrorMapper.not_found(conn, "buyer_not_found")

          {:error, reason} ->
            ErrorMapper.unprocessable(conn, "buyer_update_failed", %{reason: inspect(reason)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        ErrorMapper.not_found(conn, "company_not_found")

      company ->
        case Buyers.can_delete?(id) do
          {:ok, :can_delete} ->
            case Buyers.delete_buyer(id, company.id) do
              {:ok, :deleted} ->
                json(conn, %{message: "Buyer deleted successfully"})

              {:error, reason} ->
                ErrorMapper.unprocessable(conn, "buyer_deletion_failed", %{
                  reason: inspect(reason)
                })
            end

          {:error, :in_use, details} ->
            ErrorMapper.unprocessable(conn, "buyer_in_use", details)

          {:error, :not_found} ->
            ErrorMapper.not_found(conn, "buyer_not_found")
        end
    end
  end
end
