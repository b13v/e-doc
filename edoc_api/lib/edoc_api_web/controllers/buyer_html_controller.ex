defmodule EdocApiWeb.BuyerHTMLController do
  use EdocApiWeb, :controller

  plug(:put_view, EdocApiWeb.BuyerHTML)

  alias EdocApi.Buyers
  alias EdocApi.Companies
  alias EdocApi.Payments
  alias EdocApiWeb.ErrorHelpers

  def index(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        buyers = Buyers.list_buyers_for_company(company.id)
        buyer_support = %{count: length(buyers), show_contracts_link?: buyers != []}

        render(conn, :index,
          buyers: buyers,
          buyer_support: buyer_support,
          current_section: :buyers,
          page_title: gettext("Buyers")
        )
    end
  end

  def new(conn, _params) do
    banks = Payments.list_banks()

    render(conn, :new,
      buyer: nil,
      banks: banks,
      bank_form: %{},
      current_section: :buyers,
      page_title: gettext("New Buyer")
    )
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.get_buyer_for_company(id, company.id) do
          nil ->
            conn
            |> put_flash(:error, gettext("Buyer not found."))
            |> redirect(to: "/buyers")

          buyer ->
            bank_account = Buyers.get_default_bank_account(buyer.id)

            render(conn, :show,
              buyer: buyer,
              bank_account: bank_account,
              current_section: :buyers,
              page_title: gettext("Buyer")
            )
        end
    end
  end

  def create(conn, %{"buyer" => buyer_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.create_buyer_for_company(company.id, buyer_params) do
          {:ok, buyer} ->
            conn
            |> put_flash(
              :info,
              gettext(
                "Buyer created successfully. %{name} is ready to use in contracts and invoices.",
                name: buyer.name
              )
            )
            |> redirect(to: "/buyers")

          {:error, %Ecto.Changeset{} = changeset} ->
            banks = Payments.list_banks()

            conn
            |> put_flash(:error, validation_flash_message(changeset))
            |> render(:new,
              buyer: nil,
              changeset: changeset,
              banks: banks,
              bank_form: bank_form_from_params(buyer_params),
              current_section: :buyers,
              page_title: gettext("New Buyer")
            )

          {:error, :validation, changeset: %Ecto.Changeset{} = changeset} ->
            banks = Payments.list_banks()

            conn
            |> put_flash(:error, validation_flash_message(changeset))
            |> render(:new,
              buyer: nil,
              changeset: changeset,
              banks: banks,
              bank_form: bank_form_from_params(buyer_params),
              current_section: :buyers,
              page_title: gettext("New Buyer")
            )

          {:error, :validation, %{changeset: %Ecto.Changeset{} = changeset}} ->
            banks = Payments.list_banks()

            conn
            |> put_flash(:error, validation_flash_message(changeset))
            |> render(:new,
              buyer: nil,
              changeset: changeset,
              banks: banks,
              bank_form: bank_form_from_params(buyer_params),
              current_section: :buyers,
              page_title: gettext("New Buyer")
            )

          {:error, _reason} ->
            banks = Payments.list_banks()

            conn
            |> put_flash(
              :error,
              gettext("Failed to create buyer. Please check the form and try again.")
            )
            |> render(:new,
              buyer: nil,
              banks: banks,
              bank_form: bank_form_from_params(buyer_params),
              current_section: :buyers,
              page_title: gettext("New Buyer")
            )
        end
    end
  end

  def edit(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.get_buyer_for_company(id, company.id) do
          nil ->
            conn
            |> put_flash(:error, gettext("Buyer not found."))
            |> redirect(to: "/buyers")

          buyer ->
            banks = Payments.list_banks()

            render(conn, :edit,
              buyer: buyer,
              banks: banks,
              bank_form: bank_form_from_buyer(buyer),
              current_section: :buyers,
              page_title: gettext("Edit Buyer")
            )
        end
    end
  end

  def update(conn, %{"id" => id, "buyer" => buyer_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.update_buyer(id, buyer_params, company.id) do
          {:ok, _buyer} ->
            conn
            |> put_flash(:info, gettext("Buyer updated successfully."))
            |> redirect(to: "/buyers")

          {:error, %Ecto.Changeset{} = changeset} ->
            buyer = Buyers.get_buyer(id)
            banks = Payments.list_banks()

            conn
            |> put_flash(:error, validation_flash_message(changeset))
            |> render(:edit,
              buyer: buyer,
              changeset: changeset,
              banks: banks,
              bank_form: bank_form_from_params(buyer_params),
              current_section: :buyers,
              page_title: gettext("Edit Buyer")
            )

          {:error, :validation, changeset: %Ecto.Changeset{} = changeset} ->
            buyer = Buyers.get_buyer(id)
            banks = Payments.list_banks()

            conn
            |> put_flash(:error, validation_flash_message(changeset))
            |> render(:edit,
              buyer: buyer,
              changeset: changeset,
              banks: banks,
              bank_form: bank_form_from_params(buyer_params),
              current_section: :buyers,
              page_title: gettext("Edit Buyer")
            )

          {:error, :validation, %{changeset: %Ecto.Changeset{} = changeset}} ->
            buyer = Buyers.get_buyer(id)
            banks = Payments.list_banks()

            conn
            |> put_flash(:error, validation_flash_message(changeset))
            |> render(:edit,
              buyer: buyer,
              changeset: changeset,
              banks: banks,
              bank_form: bank_form_from_params(buyer_params),
              current_section: :buyers,
              page_title: gettext("Edit Buyer")
            )

          {:error, :not_found} ->
            conn
            |> put_flash(:error, gettext("Buyer not found."))
            |> redirect(to: "/buyers")

          {:error, :not_found, _details} ->
            conn
            |> put_flash(:error, gettext("Buyer not found."))
            |> redirect(to: "/buyers")

          {:error, _reason} ->
            buyer = Buyers.get_buyer(id)
            banks = Payments.list_banks()

            conn
            |> put_flash(
              :error,
              gettext("Failed to update buyer. Please check the form and try again.")
            )
            |> render(:edit,
              buyer: buyer,
              banks: banks,
              bank_form: bank_form_from_params(buyer_params),
              current_section: :buyers,
              page_title: gettext("Edit Buyer")
            )
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.delete_buyer(id, company.id) do
          {:ok, :deleted} ->
            conn
            |> put_flash(:info, gettext("Buyer deleted successfully."))
            |> redirect(to: "/buyers")

          {:error, :in_use, details} ->
            conn
            |> put_flash(
              :error,
              gettext(
                "Cannot delete buyer: used in %{contract_count} contract(s) and %{invoice_count} invoice(s).",
                contract_count: details.contract_count,
                invoice_count: details.invoice_count
              )
            )
            |> redirect(to: "/buyers")

          {:error, :not_found} ->
            conn
            |> put_flash(:error, gettext("Buyer not found."))
            |> redirect(to: "/buyers")
        end
    end
  end

  defp validation_flash_message(changeset) do
    if Keyword.has_key?(changeset.errors, :bin_iin) do
      gettext("Invalid BIN/IIN. Please enter a valid 12-digit BIN/IIN.")
    else
      if Keyword.has_key?(changeset.errors, :iban) do
        gettext("Check the IBAN number. It must be exactly 20 alphanumeric characters.")
      else
        ErrorHelpers.format_changeset_errors(changeset)
      end
    end
  end

  defp bank_form_from_params(params) do
    %{
      "bank_id" => Map.get(params, "bank_id", ""),
      "iban" => Map.get(params, "iban", ""),
      "bic" => Map.get(params, "bic", "")
    }
  end

  defp bank_form_from_buyer(buyer) do
    case Buyers.get_default_bank_account(buyer.id) do
      nil ->
        %{"bank_id" => "", "iban" => "", "bic" => ""}

      account ->
        %{
          "bank_id" => account.bank_id || "",
          "iban" => account.iban || "",
          "bic" => account.bic || (account.bank && account.bank.bic) || ""
        }
    end
  end
end
