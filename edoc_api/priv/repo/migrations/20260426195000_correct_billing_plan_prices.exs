defmodule EdocApi.Repo.Migrations.CorrectBillingPlanPrices do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE plans
    SET price_kzt = 2900, updated_at = NOW()
    WHERE code = 'starter'
    """)

    execute("""
    UPDATE plans
    SET price_kzt = 5900, updated_at = NOW()
    WHERE code = 'basic'
    """)

    execute("""
    UPDATE billing_invoices
    SET amount_kzt = 2900, updated_at = NOW()
    WHERE status = 'draft' AND plan_snapshot_code = 'starter'
    """)

    execute("""
    UPDATE billing_invoices
    SET amount_kzt = 5900, updated_at = NOW()
    WHERE status = 'draft' AND plan_snapshot_code = 'basic'
    """)
  end

  def down do
    :ok
  end
end
