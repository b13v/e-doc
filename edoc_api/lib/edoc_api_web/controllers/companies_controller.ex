defmodule EdocApiWeb.CompaniesController do
  use EdocApiWeb, :controller

  import Ecto.Query, warn: false

  alias EdocApi.Companies
  alias EdocApi.Payments
  alias EdocApi.Repo
  alias EdocApi.Core.CompanyBankAccount

  # Setup page for new users (create company)
  def setup(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        banks = Payments.list_banks()
        kbe_codes = Payments.list_kbe_codes()
        knp_codes = Payments.list_knp_codes()

        render(conn, :setup,
          company: nil,
          banks: banks,
          kbe_codes: kbe_codes,
          knp_codes: knp_codes,
          page_title: "Set Up Your Company"
        )

      _company ->
        # User already has a company, redirect to edit page
        redirect(conn, to: "/company")
    end
  end

  def create_setup(conn, %{"company" => company_params, "bank_account" => bank_account_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        banks = Payments.list_banks()
        kbe_codes = Payments.list_kbe_codes()
        knp_codes = Payments.list_knp_codes()

        # First create the company
        case Companies.upsert_company_for_user(user.id, company_params) do
          {:ok, company, _warnings} ->
            # Then create the bank account
            bank_account_attrs = Map.put(bank_account_params, "label", "Primary Account")

            case Payments.create_company_bank_account_for_user(user.id, bank_account_attrs) do
              {:ok, _bank_account} ->
                conn
                |> put_flash(
                  :info,
                  "Компания успешно зарегистрирована! Теперь добавьте своего первого покупателя, чтобы начать заключать договоры."
                )
                |> redirect(to: "/buyers/new")

              {:error, _changeset} ->
                conn
                |> put_flash(
                  :error,
                  "Не удалось создать банковский счет. Пожалуйста, попробуйте еще раз."
                )
                |> render(:setup,
                  company: company,
                  banks: banks,
                  kbe_codes: kbe_codes,
                  knp_codes: knp_codes,
                  page_title: "Set Up Your Company"
                )
            end

          {:error, changeset, _warnings} ->
            conn
            |> put_flash(:error, company_validation_flash_message(changeset))
            |> render(:setup,
              changeset: changeset,
              banks: banks,
              kbe_codes: kbe_codes,
              knp_codes: knp_codes,
              page_title: "Set Up Your Company"
            )
        end

      _company ->
        redirect(conn, to: "/company")
    end
  end

  def edit(conn, _params) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        # No company yet, redirect to setup
        redirect(conn, to: "/company/setup")

      company ->
        bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
        banks = Payments.list_banks()

        render(conn, :edit,
          company: company,
          bank_accounts: bank_accounts,
          banks: banks,
          page_title: "Company Settings"
        )
    end
  end

  def update(conn, %{"company" => company_params}) do
    user = conn.assigns.current_user

    case Companies.upsert_company_for_user(user.id, company_params) do
      {:ok, _company, _warnings} ->
        conn
        |> put_flash(:info, "Обновление компании прошло успешно")
        |> redirect(to: "/company")

      {:error, changeset, _warnings} ->
        company = Companies.get_company_by_user_id(user.id)
        bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
        banks = Payments.list_banks()

        conn
        |> put_flash(:error, company_validation_flash_message(changeset))
        |> render(:edit,
          company: company,
          bank_accounts: bank_accounts,
          banks: banks,
          changeset: changeset,
          page_title: "Company Settings"
        )
    end
  end

  # Bank account actions
  def add_bank_account(conn, %{"bank_account" => bank_account_params}) do
    user = conn.assigns.current_user

    case Payments.create_company_bank_account_for_user(user.id, bank_account_params) do
      {:ok, _bank_account} ->
        conn
        |> put_flash(:info, "Банковский счет успешно добавлен.")
        |> redirect(to: "/company")

      {:error, _changeset} ->
        company = Companies.get_company_by_user_id(user.id)
        bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
        banks = Payments.list_banks()

        render(conn, :edit,
          company: company,
          bank_accounts: bank_accounts,
          banks: banks,
          page_title: "Company Settings"
        )
    end
  end

  def set_default_bank_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Payments.set_default_bank_account(user.id, id) do
      {:ok, _bank_account} ->
        conn
        |> put_flash(:info, "Обновлен банковский счет по умолчанию.")
        |> redirect(to: "/company")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Не удалось обновить банковский счет по умолчанию.")
        |> redirect(to: "/company")
    end
  end

  def delete_bank_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Компания не найдена")
        |> redirect(to: "/company")

      company ->
        accounts = Payments.list_company_bank_accounts_for_user(user.id)

        cond do
          Enum.empty?(accounts) ->
            conn
            |> put_flash(:error, "Банковский счет не найден")
            |> redirect(to: "/company")

          Enum.all?(accounts, fn account -> account.id != id end) ->
            conn
            |> put_flash(:error, "Банковский счет не найден")
            |> redirect(to: "/company")

          length(accounts) == 1 ->
            conn
            |> put_flash(:error, "Невозможно удалить единственный банковский счет.")
            |> redirect(to: "/company")

          true ->
            {deleted_count, _} =
              CompanyBankAccount
              |> where([a], a.id == ^id and a.company_id == ^company.id)
              |> Repo.delete_all()

            if deleted_count == 1 do
              conn
              |> put_flash(:info, "Банковский счет удален")
              |> redirect(to: "/company")
            else
              conn
              |> put_flash(:error, "Не удалось удалить банковский счет")
              |> redirect(to: "/company")
            end
        end
    end
  end

  defp company_validation_flash_message(changeset) do
    if Keyword.has_key?(changeset.errors, :bin_iin) do
      "Неверный БИН/ИИН. Пожалуйста, введите действительный 12-значный БИН/ИИН."
    else
      "Пожалуйста, исправьте ошибки, указанные ниже."
    end
  end
end
