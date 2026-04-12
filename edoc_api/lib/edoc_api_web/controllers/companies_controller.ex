defmodule EdocApiWeb.CompaniesController do
  use EdocApiWeb, :controller

  import Ecto.Query, warn: false
  require Logger

  alias EdocApi.Companies
  alias EdocApi.EmailSender
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
        render_company_settings(conn, user, company)
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
        if Monetization.can_manage_billing_and_team?(company.id, user.id) do
          attrs = %{
            "plan" => Map.get(subscription_params, "plan", "starter"),
            "skip_trial" => true
          }

          case Monetization.validate_plan_change(company.id, attrs["plan"]) do
            {:ok, _details} ->
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

            {:error, :seat_limit_exceeded_on_downgrade, details} ->
              conn
              |> render_company_settings(user, company, downgrade_warning: details)
          end
        else
          conn
          |> put_flash(:error, gettext("Only the owner or an admin can manage the tariff and team members."))
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
        if Monetization.can_manage_billing_and_team?(company.id, user.id) do
          case Monetization.invite_member(company.id, membership_params) do
            {:ok, membership} ->
              _ =
                case EmailSender.send_membership_invite_email(membership.invite_email, %{
                       company_name: company.name,
                       inviter_email: user.email,
                       locale: conn.assigns[:locale] || "ru"
                     }) do
                  {:ok, _receipt} ->
                    :ok

                  {:error, reason} ->
                    Logger.warning(
                      "Failed to send team invitation email to #{membership.invite_email}: #{inspect(reason)}"
                    )

                    :error
                end

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
        else
          conn
          |> put_flash(:error, gettext("Only the owner or an admin can manage the tariff and team members."))
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
        if Monetization.can_manage_billing_and_team?(company.id, user.id) do
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

            {:error, :owner_not_found} ->
              conn
              |> put_flash(
                :error,
                gettext("Team owner was not found. Please restore the owner and try again.")
              )
              |> redirect(to: "/company")

            {:error, :invoice_number_conflict_on_reassign} ->
              conn
              |> put_flash(
                :error,
                gettext(
                  "Cannot remove this member because invoice numbers conflict during reassignment."
                )
              )
              |> redirect(to: "/company")

            {:error, :reassign_failed} ->
              conn
              |> put_flash(
                :error,
                gettext("Failed to remove team member. Please try again.")
              )
              |> redirect(to: "/company")
          end
        else
          conn
          |> put_flash(:error, gettext("Only the owner or an admin can manage the tariff and team members."))
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

  defp render_company_settings(conn, user, company, extra_assigns \\ []) do
    bank_accounts = Payments.list_visible_company_bank_accounts_for_user(user.id)
    banks = Payments.list_banks()
    subscription = Monetization.subscription_snapshot(company.id)
    memberships = Monetization.list_memberships(company.id)
    can_manage_billing_and_team = Monetization.can_manage_billing_and_team?(company.id, user.id)

    assigns =
      [
        company: company,
        bank_accounts: bank_accounts,
        banks: banks,
        subscription: subscription,
        memberships: memberships,
        can_manage_billing_and_team: can_manage_billing_and_team,
        current_section: :company,
        page_title: gettext("Company Settings")
      ]
      |> Keyword.merge(extra_assigns)

    render(conn, :edit, assigns)
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
