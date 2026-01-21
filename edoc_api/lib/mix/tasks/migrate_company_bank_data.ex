defmodule Mix.Tasks.MigrateCompanyBankData do
  @moduledoc """
  One-time data migration: Copy company bank data to company_bank_accounts table.

  This task migrates legacy bank data from the companies table (bank_name, iban,
  bank_id, kbe_code_id, knp_code_id) to the company_bank_accounts table.

  ## Usage

      mix migrate_company_bank_data

  ## Options

      --dry-run    Show what would be migrated without making changes

  ## Example

      mix migrate_company_bank_data
      mix migrate_company_bank_data --dry-run
  """
  use Mix.Task

  import Ecto.Query
  alias EdocApi.Repo
  alias EdocApi.Core.{Company, CompanyBankAccount}

  @shortdoc "Migrate company bank data to company_bank_accounts table"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    dry_run = "--dry-run" in args

    if dry_run do
      Mix.shell().info("🔍 DRY RUN MODE - No changes will be made\n")
    end

    companies_with_bank_data =
      Company
      |> where([c], not is_nil(c.iban) and not is_nil(c.bank_id))
      |> Repo.all()
      |> Repo.preload([:bank, :kbe_code, :knp_code, :bank_accounts])

    Mix.shell().info(
      "Found #{length(companies_with_bank_data)} companies with legacy bank data\n"
    )

    Enum.each(companies_with_bank_data, fn company ->
      migrate_company(company, dry_run)
    end)

    Mix.shell().info("\n✅ Migration complete!")

    unless dry_run do
      Mix.shell().info(
        "\n⚠️  Next steps:\n" <>
          "   1. Verify bank accounts were created correctly\n" <>
          "   2. Update any UI/forms to use company_bank_accounts instead of company fields\n" <>
          "   3. Consider running a schema migration to drop deprecated columns later"
      )
    end
  end

  defp migrate_company(company, dry_run) do
    # Check if company already has a bank account with this IBAN
    existing_account =
      CompanyBankAccount
      |> where([a], a.company_id == ^company.id and a.iban == ^company.iban)
      |> Repo.one()

    if existing_account do
      Mix.shell().info(
        "⏭️  Skipping company #{company.name} - bank account already exists (#{existing_account.label})"
      )
    else
      bank_name = company.bank_name || (company.bank && company.bank.name) || "Primary Account"

      attrs = %{
        "company_id" => company.id,
        "label" => bank_name,
        "iban" => company.iban,
        "bank_id" => company.bank_id,
        "kbe_code_id" => company.kbe_code_id,
        "knp_code_id" => company.knp_code_id,
        "is_default" => true
      }

      if dry_run do
        Mix.shell().info("Would create bank account for company #{company.name}:")
        Mix.shell().info("  - Label: #{bank_name}")
        Mix.shell().info("  - IBAN: #{company.iban}")
        Mix.shell().info("  - Bank: #{company.bank && company.bank.name}")
        Mix.shell().info("  - KBE: #{company.kbe_code && company.kbe_code.code}")
        Mix.shell().info("  - KNP: #{company.knp_code && company.knp_code.code}\n")
      else
        case create_bank_account(attrs, company.id) do
          {:ok, _account} ->
            Mix.shell().info("✅ Created bank account for company #{company.name}")

          {:error, changeset} ->
            Mix.shell().error("❌ Failed to create bank account for company #{company.name}:")

            Enum.each(changeset.errors, fn {field, {message, _}} ->
              Mix.shell().error("   #{field}: #{message}")
            end)
        end
      end
    end
  end

  defp create_bank_account(attrs, company_id) do
    %CompanyBankAccount{}
    |> CompanyBankAccount.changeset(attrs, company_id)
    |> Repo.insert()
  end
end
