defmodule EdocApiWeb.BuyersController do
  use EdocApiWeb, :controller

  require Logger

  alias EdocApi.Buyers
  alias EdocApi.Companies
  alias EdocApi.Repo
  alias EdocApiWeb.{ControllerHelpers, ErrorMapper}

  action_fallback(EdocApiWeb.FallbackController)

  def index(conn, params) do
    user = conn.assigns.current_user

    %{page: page, page_size: page_size, offset: offset} =
      ControllerHelpers.pagination_params(params)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        render(conn, :index,
          buyers: [],
          meta: ControllerHelpers.pagination_meta(page, page_size, 0)
        )

      company ->
        buyers =
          Buyers.list_buyers_for_company(company.id, limit: page_size, offset: offset)
          |> Repo.preload(bank_accounts: :bank)

        total_count = Buyers.count_buyers_for_company(company.id)

        render(conn, :index,
          buyers: buyers,
          meta: ControllerHelpers.pagination_meta(page, page_size, total_count)
        )
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
            buyer = Repo.preload(buyer, bank_accounts: :bank)
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
            buyer = Repo.preload(buyer, bank_accounts: :bank)

            conn
            |> put_status(:created)
            |> render(:show, buyer: buyer)

          {:error, %Ecto.Changeset{} = changeset} ->
            ErrorMapper.validation(conn, changeset)

          {:error, :validation, changeset: %Ecto.Changeset{} = changeset} ->
            ErrorMapper.validation(conn, changeset)

          {:error, :validation, %{changeset: %Ecto.Changeset{} = changeset}} ->
            ErrorMapper.validation(conn, changeset)

          {:error, reason} ->
            Logger.warning("Buyer creation failed: #{inspect(reason)}")

            ErrorMapper.unprocessable(conn, "buyer_creation_failed", %{
              message: "Unable to create buyer. Please try again."
            })
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
            buyer = Repo.preload(buyer, bank_accounts: :bank)
            render(conn, :show, buyer: buyer)

          {:error, %Ecto.Changeset{} = changeset} ->
            ErrorMapper.validation(conn, changeset)

          {:error, :validation, changeset: %Ecto.Changeset{} = changeset} ->
            ErrorMapper.validation(conn, changeset)

          {:error, :validation, %{changeset: %Ecto.Changeset{} = changeset}} ->
            ErrorMapper.validation(conn, changeset)

          {:error, :not_found, _details} ->
            ErrorMapper.not_found(conn, "buyer_not_found")

          {:error, reason} ->
            Logger.warning("Buyer update failed: #{inspect(reason)}")

            ErrorMapper.unprocessable(conn, "buyer_update_failed", %{
              message: "Unable to update buyer. Please try again."
            })
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

              {:error, :not_found, _details} ->
                ErrorMapper.not_found(conn, "buyer_not_found")

              {:error, reason} ->
                Logger.warning("Buyer deletion failed: #{inspect(reason)}")

                ErrorMapper.unprocessable(conn, "buyer_deletion_failed", %{
                  message: "Unable to delete buyer. Please try again."
                })
            end

          {:error, :in_use, details} ->
            ErrorMapper.unprocessable(conn, "buyer_in_use", details)
        end
    end
  end
end
