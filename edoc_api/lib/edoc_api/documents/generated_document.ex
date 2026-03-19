defmodule EdocApi.Documents.GeneratedDocument do
  @moduledoc """
  Stores asynchronously generated PDF documents.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "generated_documents" do
    field(:document_type, :string)
    field(:document_id, :binary_id)
    field(:pdf_binary, :binary)
    field(:file_path, :string)
    field(:status, :string, default: "pending")
    field(:error_message, :string)

    belongs_to(:user, EdocApi.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(generated_document, attrs) do
    generated_document
    |> cast(attrs, [
      :user_id,
      :document_type,
      :document_id,
      :pdf_binary,
      :file_path,
      :status,
      :error_message
    ])
    |> validate_required([:user_id, :document_type, :document_id, :status])
    |> validate_inclusion(:status, ~w(pending processing completed failed))
    |> validate_inclusion(:document_type, ~w(contract invoice act))
    |> unique_constraint([:document_type, :document_id],
      name: :unique_document_pdf_pending
    )
  end

  def status_values, do: ~w(pending processing completed failed)
  def document_type_values, do: ~w(contract invoice act)
end
