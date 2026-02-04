defmodule EdocApiWeb.CompaniesController do
  use EdocApiWeb, :controller

  alias EdocApi.Companies
  alias EdocApi.Payments

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
                  "Company set up successfully! Now add your first buyer to start creating contracts."
                )
                |> redirect(to: "/buyers/new")

              {:error, _changeset} ->
                conn
                |> put_flash(:error, "Failed to create bank account. Please try again.")
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
            |> put_flash(:error, "Please fix the errors below.")
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
        kbe_codes = Payments.list_kbe_codes()
        knp_codes = Payments.list_knp_codes()

        render(conn, :edit,
          company: company,
          bank_accounts: bank_accounts,
          banks: banks,
          kbe_codes: kbe_codes,
          knp_codes: knp_codes,
          page_title: "Company Settings"
        )
    end
  end

  def update(conn, %{"company" => company_params}) do
    user = conn.assigns.current_user

    case Companies.upsert_company_for_user(user.id, company_params) do
      {:ok, _company, _warnings} ->
        conn
        |> put_flash(:info, "Company updated successfully")
        |> redirect(to: "/company")

      {:error, changeset, _warnings} ->
        company = Companies.get_company_by_user_id(user.id)
        bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
        banks = Payments.list_banks()
        kbe_codes = Payments.list_kbe_codes()
        knp_codes = Payments.list_knp_codes()

        render(conn, :edit,
          company: company,
          bank_accounts: bank_accounts,
          banks: banks,
          kbe_codes: kbe_codes,
          knp_codes: knp_codes,
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
        |> put_flash(:info, "Bank account added successfully")
        |> redirect(to: "/company")

      {:error, _changeset} ->
        company = Companies.get_company_by_user_id(user.id)
        bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
        banks = Payments.list_banks()
        kbe_codes = Payments.list_kbe_codes()
        knp_codes = Payments.list_knp_codes()

        render(conn, :edit,
          company: company,
          bank_accounts: bank_accounts,
          banks: banks,
          kbe_codes: kbe_codes,
          knp_codes: knp_codes,
          page_title: "Company Settings"
        )
    end
  end

  def set_default_bank_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Payments.set_default_bank_account(user.id, id) do
      {:ok, _bank_account} ->
        conn
        |> put_flash(:info, "Default bank account updated")
        |> redirect(to: "/company")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to update default bank account")
        |> redirect(to: "/company")
    end
  end

  def delete_bank_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    # Get the bank account and verify ownership
    case Payments.list_company_bank_accounts_for_user(user.id)
         |> Enum.find(fn acc -> acc.id == id end) do
      nil ->
        conn
        |> put_flash(:error, "Bank account not found")
        |> redirect(to: "/company")

      _bank_account ->
        # Don't allow deleting the only bank account
        accounts = Payments.list_company_bank_accounts_for_user(user.id)

        if length(accounts) == 1 do
          conn
          |> put_flash(:error, "Cannot delete the only bank account")
          |> redirect(to: "/company")
        else
          EdocApi.Repo.delete(EdocApi.Repo.get(EdocApi.Core.CompanyBankAccount, id))

          conn
          |> put_flash(:info, "Bank account deleted")
          |> redirect(to: "/company")
        end
    end
  end
end
