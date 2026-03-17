defmodule EdocApiWeb.BuyerHTMLController do
  use EdocApiWeb, :controller

  plug(:put_view, EdocApiWeb.BuyerHTML)

  alias EdocApi.Buyers
  alias EdocApi.Companies
  alias EdocApi.Payments

  def index(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Пожалуйста, сначала зарегистрируйте свою компанию.")
        |> redirect(to: "/company/setup")

      company ->
        buyers = Buyers.list_buyers_for_company(company.id)
        render(conn, :index, buyers: buyers, page_title: "Buyers")
    end
  end

  def new(conn, _params) do
    banks = Payments.list_banks()
    render(conn, :new, buyer: nil, banks: banks, bank_form: %{}, page_title: "New Buyer")
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Пожалуйста, сначала зарегистрируйте свою компанию.")
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.get_buyer_for_company(id, company.id) do
          nil ->
            conn
            |> put_flash(:error, "Покупатель не найден.")
            |> redirect(to: "/buyers")

          buyer ->
            bank_account = Buyers.get_default_bank_account(buyer.id)
            render(conn, :show, buyer: buyer, bank_account: bank_account, page_title: "Buyer")
        end
    end
  end

  def create(conn, %{"buyer" => buyer_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Пожалуйста, сначала зарегистрируйте свою компанию.")
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.create_buyer_for_company(company.id, buyer_params) do
          {:ok, buyer} ->
            conn
            |> put_flash(
              :info,
              "Покупатель успешно создан! #{buyer.name} готов к использованию в договорах и счетах на оплату."
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
              page_title: "New Buyer"
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
              page_title: "New Buyer"
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
              page_title: "New Buyer"
            )

          {:error, _reason} ->
            banks = Payments.list_banks()

            conn
            |> put_flash(
              :error,
              "Не удалось создать покупателя. Пожалуйста, проверьте форму и попробуйте снова."
            )
            |> render(:new,
              buyer: nil,
              banks: banks,
              bank_form: bank_form_from_params(buyer_params),
              page_title: "New Buyer"
            )
        end
    end
  end

  def edit(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Пожалуйста, сначала зарегистрируйте свою компанию.")
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.get_buyer_for_company(id, company.id) do
          nil ->
            conn
            |> put_flash(:error, "Покупатель не найден.")
            |> redirect(to: "/buyers")

          buyer ->
            banks = Payments.list_banks()

            render(conn, :edit,
              buyer: buyer,
              banks: banks,
              bank_form: bank_form_from_buyer(buyer),
              page_title: "Edit Buyer"
            )
        end
    end
  end

  def update(conn, %{"id" => id, "buyer" => buyer_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Пожалуйста, сначала зарегистрируйте свою компанию.")
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.update_buyer(id, buyer_params, company.id) do
          {:ok, _buyer} ->
            conn
            |> put_flash(:info, "Информация покупателя успешно обновлена.")
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
              page_title: "Edit Buyer"
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
              page_title: "Edit Buyer"
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
              page_title: "Edit Buyer"
            )

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Покупатель не найден.")
            |> redirect(to: "/buyers")

          {:error, :not_found, _details} ->
            conn
            |> put_flash(:error, "Покупатель не найден.")
            |> redirect(to: "/buyers")

          {:error, _reason} ->
            buyer = Buyers.get_buyer(id)
            banks = Payments.list_banks()

            conn
            |> put_flash(
              :error,
              "Не удалось обновить информацию о покупателе. Пожалуйста, проверьте форму и попробуйте снова."
            )
            |> render(:edit,
              buyer: buyer,
              banks: banks,
              bank_form: bank_form_from_params(buyer_params),
              page_title: "Edit Buyer"
            )
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Пожалуйста, сначала зарегистрируйте свою компанию.")
        |> redirect(to: "/company/setup")

      company ->
        case Buyers.delete_buyer(id, company.id) do
          {:ok, :deleted} ->
            conn
            |> put_flash(:info, "Покупатель успешно удален.")
            |> redirect(to: "/buyers")

          {:error, :in_use, details} ->
            conn
            |> put_flash(
              :error,
              "Невозможно удалить покупателя: используется в #{details.contract_count} договоре(ах) и #{details.invoice_count} счете(ах) на оплату"
            )
            |> redirect(to: "/buyers")

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Покупатель не найден.")
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

  defp validation_flash_message(changeset) do
    if Keyword.has_key?(changeset.errors, :bin_iin) do
      "Неверный БИН/ИИН. Пожалуйста, введите действительный 12-значный БИН/ИИН."
    else
      format_changeset_errors(changeset)
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
