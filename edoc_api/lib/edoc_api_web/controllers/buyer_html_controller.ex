defmodule EdocApiWeb.BuyerHTMLController do
  use EdocApiWeb, :controller

  alias EdocApi.Buyers
  alias EdocApi.Companies

  def index(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company/setup")

      company ->
        buyers = Buyers.list_buyers_for_company(company.id)
        render(conn, :index, buyers: buyers, page_title: "Buyers")
    end
  end

  def new(conn, _params) do
    render(conn, :new, buyer: nil, page_title: "New Buyer")
  end

  def create(conn, %{"buyer" => buyer_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.create_buyer_for_company(company.id, buyer_params) do
          {:ok, buyer} ->
            conn
            |> put_flash(
              :info,
              "Buyer created successfully! #{buyer.name} is ready to use in contracts and invoices."
            )
            |> redirect(to: "/buyers")

          {:error, changeset} ->
            conn
            |> put_flash(:error, format_changeset_errors(changeset))
            |> render(:new, buyer: nil, changeset: changeset, page_title: "New Buyer")
        end
    end
  end

  def edit(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.get_buyer_for_company(id, company.id) do
          nil ->
            conn
            |> put_flash(:error, "Buyer not found")
            |> redirect(to: "/buyers")

          buyer ->
            render(conn, :edit, buyer: buyer, page_title: "Edit Buyer")
        end
    end
  end

  def update(conn, %{"id" => id, "buyer" => buyer_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.update_buyer(id, buyer_params, company.id) do
          {:ok, _buyer} ->
            conn
            |> put_flash(:info, "Buyer updated successfully")
            |> redirect(to: "/buyers")

          {:error, changeset} ->
            buyer = Buyers.get_buyer(id)

            conn
            |> put_flash(:error, format_changeset_errors(changeset))
            |> render(:edit, buyer: buyer, changeset: changeset, page_title: "Edit Buyer")
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Please set up your company first")
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.delete_buyer(id, company.id) do
          {:ok, :deleted} ->
            conn
            |> put_flash(:info, "Buyer deleted successfully")
            |> redirect(to: "/buyers")

          {:error, :in_use, details} ->
            conn
            |> put_flash(
              :error,
              "Cannot delete buyer: used in #{details.contract_count} contract(s) and #{details.invoice_count} invoice(s)"
            )
            |> redirect(to: "/buyers")

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Buyer not found")
            |> redirect(to: "/buyers")
        end
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end
end
