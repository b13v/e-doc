defmodule EdocApi.Repo.Migrations.AddGeneratedDocumentsTable do
  use Ecto.Migration

  def change do
    create table(:generated_documents, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, :binary_id, null: false)
      add(:document_type, :string, null: false)
      add(:document_id, :binary_id, null: false)
      add(:pdf_binary, :bytea)
      add(:file_path, :string)
      add(:status, :string, default: "pending", null: false)
      add(:error_message, :text)
      timestamps(type: :utc_datetime)
    end

    create(index(:generated_documents, [:user_id]))
    create(index(:generated_documents, [:document_type, :document_id]))
    create(index(:generated_documents, [:status]))
    create(index(:generated_documents, [:inserted_at]))

    create(
      unique_index(:generated_documents, [:document_type, :document_id],
        name: :unique_document_pdf_pending
      )
    )
  end
end
