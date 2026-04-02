defmodule EdocApi.Repo.Migrations.CreateMonetizationTables do
  use Ecto.Migration

  def change do
    create table(:tenant_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all), null: false
      add :plan, :string, null: false
      add :status, :string, null: false, default: "active"
      add :period_start, :utc_datetime, null: false
      add :period_end, :utc_datetime, null: false
      add :included_document_limit, :integer, null: false, default: 10
      add :included_seat_limit, :integer, null: false, default: 2
      add :add_on_seat_quantity, :integer, null: false, default: 0
      add :trial_document_limit, :integer, null: false, default: 10
      add :trial_started_at, :utc_datetime
      add :trial_ended_at, :utc_datetime
      add :skip_trial, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:tenant_subscriptions, [:company_id])
    create index(:tenant_subscriptions, [:company_id, :status])
    create index(:tenant_subscriptions, [:company_id, :inserted_at])

    create table(:tenant_usage_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :document_type, :string, null: false
      add :document_id, :binary_id, null: false
      add :occurred_at, :utc_datetime, null: false
      add :period_start, :utc_datetime, null: false
      add :period_end, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:tenant_usage_events, [:company_id, :occurred_at])
    create unique_index(:tenant_usage_events, [:company_id, :document_type, :document_id])

    create table(:tenant_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenant_memberships, [:company_id, :user_id])
    create index(:tenant_memberships, [:company_id, :status])
    create index(:tenant_memberships, [:user_id, :status])
  end
end
