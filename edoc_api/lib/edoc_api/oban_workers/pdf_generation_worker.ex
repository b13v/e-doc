defmodule EdocApi.ObanWorkers.PdfGenerationWorker do
  @moduledoc """
  Background worker for async PDF generation.

  This worker generates PDFs for contracts, invoices, and acts.
  The PDF is stored in the generated_documents table for later retrieval.
  """
  use Oban.Worker
  require Logger

  alias EdocApi.{Core, Invoicing, Acts, Repo}
  alias EdocApi.Documents.GeneratedDocument

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    document_type = Map.get(args, "document_type")
    document_id = Map.get(args, "document_id")
    user_id = Map.get(args, "user_id")

    Logger.info("Generating PDF for #{document_type} #{document_id}")

    with {:ok, record} <- fetch_document(document_type, document_id, user_id),
         {:ok, pdf_binary} <- generate_pdf(document_type, record),
         {:ok, _} <- store_pdf(document_type, document_id, user_id, pdf_binary) do
      Logger.info("Successfully generated PDF for #{document_type} #{document_id}")
      :ok
    else
      {:error, :not_found} ->
        Logger.warning("Document not found: #{document_type} #{document_id}")
        mark_failed(document_type, document_id, user_id, "Document not found")
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("Failed to generate PDF: #{inspect(reason)}")
        mark_failed(document_type, document_id, user_id, inspect(reason))
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)

  # Enqueue a PDF generation job
  def enqueue(document_type, document_id, user_id)
      when document_type in ~w(contract invoice act) do
    %{
      "document_type" => document_type,
      "document_id" => document_id,
      "user_id" => user_id
    }
    |> Oban.Job.new(queue: :pdf_generation, max_attempts: 3)
    |> Oban.insert()
  end

  # Check if a PDF is ready for a document
  def ready?(document_type, document_id) do
    case Repo.get_by(GeneratedDocument,
           document_type: to_string(document_type),
           document_id: document_id,
           status: "completed"
         ) do
      nil -> {:error, :not_found}
      doc -> {:ok, doc}
    end
  end

  # Get the PDF binary for a document
  def get_pdf(document_type, document_id) do
    case Repo.get_by(GeneratedDocument,
           document_type: to_string(document_type),
           document_id: document_id,
           status: "completed"
         ) do
      nil -> {:error, :not_found}
      %{pdf_binary: pdf} when is_binary(pdf) -> {:ok, pdf}
      %{file_path: path} when is_binary(path) -> File.read(path)
    end
  end

  # Private functions

  defp fetch_document("contract", id, user_id) do
    case Core.get_contract_for_user(user_id, id) do
      {:ok, contract} -> {:ok, contract}
      {:error, :not_found, _} -> {:error, :not_found}
    end
  end

  defp fetch_document("invoice", id, user_id) do
    case Invoicing.get_invoice_for_user(user_id, id) do
      nil -> {:error, :not_found}
      invoice -> {:ok, invoice}
    end
  end

  defp fetch_document("act", id, user_id) do
    case Acts.get_act_for_user(user_id, id) do
      nil -> {:error, :not_found}
      act -> {:ok, act}
    end
  end

  defp generate_pdf("contract", contract) do
    html = EdocApiWeb.PdfTemplates.contract_html(contract)
    EdocApi.Documents.ContractPdf.render(html)
  end

  defp generate_pdf("invoice", invoice) do
    html = EdocApiWeb.PdfTemplates.invoice_html(invoice)
    EdocApi.Documents.InvoicePdf.render(html)
  end

  defp generate_pdf("act", act) do
    html = EdocApiWeb.PdfTemplates.act_html(act)
    EdocApi.Documents.ActPdf.render(html)
  end

  defp store_pdf(document_type, document_id, user_id, pdf_binary) do
    changeset =
      %GeneratedDocument{}
      |> Ecto.Changeset.change(%{
        user_id: user_id,
        document_type: to_string(document_type),
        document_id: document_id,
        pdf_binary: pdf_binary,
        status: "completed"
      })

    case Repo.insert(
           changeset,
           on_conflict: [
             set: [pdf_binary: pdf_binary, status: "completed", updated_at: DateTime.utc_now()]
           ],
           conflict_target: [:document_type, :document_id]
         ) do
      {:ok, _doc} -> {:ok, :stored}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp mark_failed(document_type, document_id, _user_id, error_message) do
    Repo.insert_all(
      GeneratedDocument,
      [
        set: [
          status: "failed",
          error_message: error_message,
          updated_at: DateTime.utc_now()
        ],
        conflict_target: [document_type: document_type, document_id: document_id]
      ],
      on_conflict: :replace_all
    )

    :ok
  end
end
