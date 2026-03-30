defmodule EdocApi.Repo.Migrations.AddSequenceNameToInvoiceCounters do
  use Ecto.Migration
  @disable_ddl_transaction false

  def up do
    # Add sequence_name column
    alter table(:invoice_counters) do
      add(:sequence_name, :string, default: "default", null: false)
    end

    # Create unique index on company_id + sequence_name
    # This replaces the old primary key constraint
    create(
      unique_index(:invoice_counters, [:company_id, :sequence_name],
        name: :invoice_counters_company_id_sequence_name_index
      )
    )

    # Update existing records to have "default" sequence name
    execute("""
    UPDATE invoice_counters
    SET sequence_name = 'default'
    WHERE sequence_name IS NULL
    """)

    # Drop the old primary key constraint
    execute("""
    ALTER TABLE invoice_counters
    DROP CONSTRAINT invoice_counters_pkey
    """)

    # Add new composite primary key
    execute("""
    ALTER TABLE invoice_counters
    ADD PRIMARY KEY (company_id, sequence_name)
    """)
  end

  def down do
    # Revert primary key change
    execute("""
    ALTER TABLE invoice_counters
    DROP CONSTRAINT invoice_counters_pkey
    """)

    # Restore old primary key
    execute("""
    ALTER TABLE invoice_counters
    ADD PRIMARY KEY (company_id)
    """)

    # Drop the unique index
    drop(
      index(:invoice_counters, [:company_id, :sequence_name],
        name: :invoice_counters_company_id_sequence_name_index
      )
    )

    # Remove sequence_name column
    alter table(:invoice_counters) do
      remove(:sequence_name)
    end
  end
end
