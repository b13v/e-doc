defmodule EdocApiWeb.CompaniesController do
  use EdocApiWeb, :controller

  import Ecto.Query, warn: false

  alias EdocApi.Companies
  alias EdocApi.Monetization
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
          page_title: gettext("Set Up Your Company")
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
            bank_account_attrs = Map.put(bank_account_params, "label", gettext("Primary Account"))

            case Payments.create_company_bank_account_for_user(user.id, bank_account_attrs) do
              {:ok, _bank_account} ->
                conn
                |> put_flash(
                  :info,
                  gettext(
                    "Company created successfully. Now add your first buyer to start working with contracts."
                  )
                )
                |> redirect(to: "/buyers/new")

              {:error, _changeset} ->
                conn
                |> put_flash(
                  :error,
                  gettext("Failed to create the bank account. Please try again.")
                )
                |> render(:setup,
                  company: company,
                  banks: banks,
                  kbe_codes: kbe_codes,
                  knp_codes: knp_codes,
                  page_title: gettext("Set Up Your Company")
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
              page_title: gettext("Set Up Your Company")
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
        bank_accounts = Payments.list_visible_company_bank_accounts_for_user(user.id)
        banks = Payments.list_banks()
        subscription = Monetization.subscription_snapshot(company.id)
        memberships = Monetization.list_memberships(company.id)

        render(conn, :edit,
          company: company,
          bank_accounts: bank_accounts,
          banks: banks,
          subscription: subscription,
          memberships: memberships,
          page_title: gettext("Company Settings")
        )
    end
  end

  def update(conn, %{"company" => company_params}) do
    user = conn.assigns.current_user

    case Companies.upsert_company_for_user(user.id, company_params) do
      {:ok, _company, _warnings} ->
        conn
        |> put_flash(:info, gettext("Company updated successfully."))
        |> redirect(to: "/company")

      {:error, changeset, _warnings} ->
        company = Companies.get_company_by_user_id(user.id)
        bank_accounts = Payments.list_visible_company_bank_accounts_for_user(user.id)
        banks = Payments.list_banks()
        subscription = Monetization.subscription_snapshot(company.id)
        memberships = Monetization.list_memberships(company.id)

        conn
        |> put_flash(:error, company_validation_flash_message(changeset))
        |> render(:edit,
          company: company,
          bank_accounts: bank_accounts,
          banks: banks,
          subscription: subscription,
          memberships: memberships,
          changeset: changeset,
          page_title: gettext("Company Settings")
        )
    end
  end

  def update_subscription(conn, %{"subscription" => subscription_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        redirect(conn, to: "/company/setup")

      company ->
        attrs = %{
          "plan" => Map.get(subscription_params, "plan", "starter"),
          "add_on_seat_quantity" => Map.get(subscription_params, "add_on_seat_quantity", 0),
          "skip_trial" => true
        }

        case Monetization.activate_subscription_for_company(company.id, attrs) do
          {:ok, _subscription} ->
            conn
            |> put_flash(:info, gettext("Subscription updated successfully."))
            |> redirect(to: "/company")

          {:error, :validation, _details} ->
            conn
            |> put_flash(:error, gettext("Failed to update the subscription."))
            |> redirect(to: "/company")

          {:error, _reason} ->
            conn
            |> put_flash(:error, gettext("Failed to update the subscription."))
            |> redirect(to: "/company")
        end
    end
  end

  # Bank account actions
  def add_bank_account(conn, %{"bank_account" => bank_account_params}) do
    user = conn.assigns.current_user

    case Payments.create_company_bank_account_for_user(user.id, bank_account_params) do
      {:ok, _bank_account} ->
        conn
        |> put_flash(:info, gettext("Bank account added successfully."))
        |> redirect(to: "/company")

      {:error, changeset} ->
        company = Companies.get_company_by_user_id(user.id)
        bank_accounts = Payments.list_visible_company_bank_accounts_for_user(user.id)
        banks = Payments.list_banks()
        subscription = Monetization.subscription_snapshot(company.id)
        memberships = Monetization.list_memberships(company.id)

        conn
        |> put_flash(:error, bank_account_validation_flash_message(changeset))
        |> render(:edit,
          company: company,
          bank_accounts: bank_accounts,
          banks: banks,
          subscription: subscription,
          memberships: memberships,
          bank_account_changeset: changeset,
          bank_account_params: bank_account_params,
          show_add_bank_form: true,
          page_title: gettext("Company Settings")
        )
    end
  end

  def invite_member(conn, %{"membership" => membership_params}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        redirect(conn, to: "/company/setup")

      company ->
        case Monetization.invite_member(company.id, membership_params) do
          {:ok, _membership} ->
            conn
            |> put_flash(:info, gettext("Team member invited successfully."))
            |> redirect(to: "/company")

          {:error, :seat_limit_reached, _details} ->
            conn
            |> put_flash(:error, gettext("No seats available. Upgrade your subscription to invite more users."))
            |> redirect(to: "/company")

          {:error, :duplicate_invite, _details} ->
            conn
            |> put_flash(:error, gettext("This email is already invited to your company."))
            |> redirect(to: "/company")

          {:error, :duplicate_member, _details} ->
            conn
            |> put_flash(:error, gettext("This user is already a team member."))
            |> redirect(to: "/company")

          {:error, :invalid_role} ->
            conn
            |> put_flash(:error, gettext("Select a valid team role."))
            |> redirect(to: "/company")

          {:error, %Ecto.Changeset{}} ->
            conn
            |> put_flash(:error, gettext("Enter a valid email address to invite a team member."))
            |> redirect(to: "/company")
        end
    end
  end

  def remove_member(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        redirect(conn, to: "/company/setup")

      company ->
        case Monetization.remove_membership(company.id, id) do
          {:ok, _membership} ->
            conn
            |> put_flash(:info, gettext("Team member removed successfully."))
            |> redirect(to: "/company")

          {:error, :last_owner} ->
            conn
            |> put_flash(:error, gettext("You cannot remove the last owner from the company."))
            |> redirect(to: "/company")

          {:error, :not_found} ->
            conn
            |> put_flash(:error, gettext("Team member not found."))
            |> redirect(to: "/company")
        end
    end
  end

  def set_default_bank_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Payments.set_default_bank_account(user.id, id) do
      {:ok, _bank_account} ->
        conn
        |> put_flash(:info, gettext("Default bank account updated."))
        |> redirect(to: "/company")

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Failed to update the default bank account."))
        |> redirect(to: "/company")
    end
  end

  def delete_bank_account(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Company not found."))
        |> redirect(to: "/company")

      company ->
        accounts = Payments.list_visible_company_bank_accounts_for_user(user.id)

        cond do
          Enum.empty?(accounts) ->
            conn
            |> put_flash(:error, gettext("Bank account not found."))
            |> redirect(to: "/company")

          Enum.all?(accounts, fn account -> account.id != id end) ->
            conn
            |> put_flash(:error, gettext("Bank account not found."))
            |> redirect(to: "/company")

          length(accounts) == 1 ->
            conn
            |> put_flash(:error, gettext("You cannot delete the only bank account."))
            |> redirect(to: "/company")

          true ->
            {deleted_count, _} =
              CompanyBankAccount
              |> where([a], a.id == ^id and a.company_id == ^company.id)
              |> Repo.delete_all()

            if deleted_count == 1 do
              conn
              |> put_flash(:info, gettext("Bank account deleted successfully."))
              |> redirect(to: "/company")
            else
              conn
              |> put_flash(:error, gettext("Failed to delete the bank account."))
              |> redirect(to: "/company")
            end
        end
    end
  end

  defp company_validation_flash_message(changeset) do
    if Keyword.has_key?(changeset.errors, :bin_iin) do
      gettext("Invalid BIN/IIN. Please enter a valid 12-digit BIN/IIN.")
    else
      gettext("Please correct the errors below.")
    end
  end

  defp bank_account_validation_flash_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_changeset_error/1)
    |> Enum.map(fn {field, errors} ->
      "#{bank_account_field_label(field)}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end

  defp translate_changeset_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(EdocApiWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(EdocApiWeb.Gettext, "errors", msg, opts)
    end
  end

  defp bank_account_field_label(:label), do: gettext("Label")
  defp bank_account_field_label(:bank_id), do: gettext("Bank")
  defp bank_account_field_label(:iban), do: gettext("IBAN")
  defp bank_account_field_label(field), do: Phoenix.Naming.humanize(field)
end
