defmodule EdocApi.Repo.Migrations.CreateBillingTables do
  use Ecto.Migration

  def change do
    create table(:plans, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:code, :string, null: false)
      add(:name, :string, null: false)
      add(:price_kzt, :integer, null: false, default: 0)
      add(:monthly_document_limit, :integer, null: false)
      add(:included_users, :integer, null: false)
      add(:is_active, :boolean, null: false, default: true)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:plans, [:code]))

    create table(:subscriptions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:plan_id, references(:plans, type: :binary_id, on_delete: :restrict), null: false)
      add(:status, :string, null: false, default: "trialing")
      add(:current_period_start, :utc_datetime, null: false)
      add(:current_period_end, :utc_datetime, null: false)
      add(:grace_until, :utc_datetime)
      add(:extra_user_seats, :integer, null: false, default: 0)
      add(:auto_renew_mode, :string, null: false, default: "manual")
      add(:next_plan_id, references(:plans, type: :binary_id, on_delete: :nilify_all))
      add(:change_effective_at, :utc_datetime)
      add(:blocked_reason, :text)

      timestamps(type: :utc_datetime)
    end

    create(index(:subscriptions, [:company_id]))
    create(index(:subscriptions, [:company_id, :status]))
    create(index(:subscriptions, [:current_period_end]))
    create(index(:subscriptions, [:plan_id]))

    create(
      unique_index(:subscriptions, [:company_id],
        name: :subscriptions_one_current_per_company_index,
        where: "status IN ('trialing', 'active', 'grace_period', 'past_due', 'suspended')"
      )
    )

    create table(:billing_invoices, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:subscription_id, references(:subscriptions, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:period_start, :utc_datetime, null: false)
      add(:period_end, :utc_datetime, null: false)
      add(:plan_snapshot_code, :string, null: false)
      add(:amount_kzt, :integer, null: false)
      add(:status, :string, null: false, default: "draft")
      add(:payment_method, :string)
      add(:kaspi_payment_link, :text)
      add(:issued_at, :utc_datetime)
      add(:due_at, :utc_datetime)
      add(:paid_at, :utc_datetime)
      add(:activated_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all))
      add(:note, :text)

      timestamps(type: :utc_datetime)
    end

    create(index(:billing_invoices, [:company_id]))
    create(index(:billing_invoices, [:company_id, :status]))
    create(index(:billing_invoices, [:company_id, :due_at]))
    create(index(:billing_invoices, [:subscription_id]))

    create table(:payments, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(
        :billing_invoice_id,
        references(:billing_invoices, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:amount_kzt, :integer, null: false)
      add(:method, :string, null: false)
      add(:status, :string, null: false, default: "pending_confirmation")
      add(:paid_at, :utc_datetime)
      add(:confirmed_at, :utc_datetime)
      add(:confirmed_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all))
      add(:external_reference, :string)
      add(:proof_attachment_url, :text)

      timestamps(type: :utc_datetime)
    end

    create(index(:payments, [:billing_invoice_id, :status]))
    create(index(:payments, [:company_id, :status]))
    create(index(:payments, [:external_reference]))

    create table(:usage_counters, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:metric, :string, null: false)
      add(:period_start, :utc_datetime, null: false)
      add(:period_end, :utc_datetime, null: false)
      add(:value, :integer, null: false, default: 0)

      timestamps(type: :utc_datetime)
    end

    create(
      unique_index(:usage_counters, [:company_id, :metric, :period_start, :period_end],
        name: :usage_counters_company_metric_period_index
      )
    )

    create table(:usage_events, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:metric, :string, null: false)
      add(:resource_type, :string, null: false)
      add(:resource_id, :binary_id, null: false)
      add(:count, :integer, null: false, default: 1)
      add(:occurred_at, :utc_datetime, null: false)
      add(:period_start, :utc_datetime, null: false)
      add(:period_end, :utc_datetime, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:usage_events, [:company_id, :period_start, :period_end]))
    create(index(:usage_events, [:company_id, :resource_type, :resource_id]))

    create table(:billing_audit_events, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:actor_user_id, references(:users, type: :binary_id, on_delete: :nilify_all))
      add(:action, :string, null: false)
      add(:subject_type, :string, null: false)
      add(:subject_id, :binary_id)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime)
    end

    create(index(:billing_audit_events, [:company_id]))
    create(index(:billing_audit_events, [:company_id, :action]))
    create(index(:billing_audit_events, [:subject_type, :subject_id]))
  end
end
