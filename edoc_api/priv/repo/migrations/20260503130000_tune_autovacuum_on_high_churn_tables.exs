defmodule EdocApi.Repo.Migrations.TuneAutovacuumOnHighChurnTables do
  use Ecto.Migration

  @tables [
    "oban_jobs",
    "generated_documents",
    "billing_invoices",
    "payments",
    "usage_events",
    "usage_counters",
    "billing_audit_events",
    "document_deliveries",
    "public_access_tokens",
    "refresh_tokens",
    "email_verification_tokens",
    "password_reset_tokens"
  ]

  def up do
    Enum.each(@tables, fn table ->
      execute("""
      ALTER TABLE IF EXISTS #{table} SET (
        autovacuum_vacuum_scale_factor = 0.03,
        autovacuum_analyze_scale_factor = 0.03
      )
      """)
    end)

    execute("""
    ALTER TABLE IF EXISTS oban_jobs SET (
      autovacuum_vacuum_scale_factor = 0.01,
      autovacuum_analyze_scale_factor = 0.02
    )
    """)
  end

  def down do
    Enum.each(@tables, fn table ->
      execute("""
      ALTER TABLE IF EXISTS #{table} RESET (
        autovacuum_vacuum_scale_factor,
        autovacuum_analyze_scale_factor
      )
      """)
    end)
  end
end
