defmodule EdocApi.ObanWorkers.PdfGenerationWorker do
  @moduledoc """
  Background worker for async PDF generation.

  This worker generates PDFs for contracts, invoices, and acts.
  The PDF is stored in the generated_documents table for later retrieval.

  ## Dependency Inversion

  This worker accepts HTML as a binary argument (provided by the web layer)
  rather than importing from EdocApiWeb, maintaining proper core→web separation.

  ## Usage

      # In web layer controller:
      html = PdfTemplates.contract_html(contract)
      PdfGenerationWorker.enqueue("contract", contract.id, user.id, html)

  ## Direct Generation (for testing or fallback)

      # When you have the document record but need HTML rendering:
      {:ok, pdf} = PdfGenerationWorker.generate_direct("contract", contract, render_fn)
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
    html_binary = Map.get(args, "html")

    Logger.info("Generating PDF for #{document_type} #{document_id}")

    with {:ok, _record} <- fetch_document(document_type, document_id, user_id),
         {:ok, pdf_binary} <- generate_pdf(document_type, html_binary),
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

  @doc """
  Enqueue a PDF generation job.

  ## Parameters

    * `document_type` - "contract", "invoice", or "act"
    * `document_id` - The UUID of the document
    * `user_id` - The UUID of the user who owns the document
    * `html_binary` - Pre-rendered HTML binary (from PdfTemplates)

  ## Example

      html = PdfTemplates.contract_html(contract)
      {:ok, job} = PdfGenerationWorker.enqueue("contract", contract.id, user.id, html)
  """
  def enqueue(document_type, document_id, user_id, html_binary)
      when document_type in ~w(contract invoice act) and is_binary(html_binary) do
    %{
      "document_type" => document_type,
      "document_id" => document_id,
      "user_id" => user_id,
      "html" => html_binary
    }
    |> Oban.Job.new(queue: :pdf_generation, max_attempts: 3)
    |> Oban.insert()
  end

  @doc """
  Check if a PDF is ready for a document.
  """
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

  @doc """
  Get the PDF binary for a document.

  Validates that the document belongs to the user before returning.
  """
  def get_pdf(document_type, document_id, user_id) do
    case Repo.get_by(GeneratedDocument,
           document_type: to_string(document_type),
           document_id: document_id,
           user_id: user_id,
           status: "completed"
         ) do
      nil -> {:error, :not_found}
      %{pdf_binary: pdf} when is_binary(pdf) -> {:ok, pdf}
      %{file_path: path} when is_binary(path) -> File.read(path)
    end
  end

  @doc """
  Generate PDF directly (synchronous, without enqueuing).

  Useful for tests or when immediate PDF generation is needed.

  ## Parameters

    * `document_type` - "contract", "invoice", or "act"
    * `record` - The document struct (Contract, Invoice, or Act)
    * `html_binary` - Pre-rendered HTML binary

  ## Example

      html = PdfTemplates.contract_html(contract)
      {:ok, pdf} = PdfGenerationWorker.generate_direct("contract", contract, html)
  """
  def generate_direct(document_type, _record, html_binary)
      when document_type in ~w(contract invoice act) and is_binary(html_binary) do
    with {:ok, pdf_binary} <- generate_pdf(document_type, html_binary) do
      {:ok, pdf_binary}
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

  defp generate_pdf("contract", html) when is_binary(html) do
    EdocApi.Documents.ContractPdf.render(html)
  end

  defp generate_pdf("invoice", html) when is_binary(html) do
    EdocApi.Documents.InvoicePdf.render(html)
  end

  defp generate_pdf("act", html) when is_binary(html) do
    EdocApi.Documents.ActPdf.render(html)
  end

  defp generate_pdf(_, _), do: {:error, :invalid_html}

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

  defp mark_failed(document_type, document_id, user_id, error_message) do
    # Create or update the failed record
    attrs = %{
      user_id: user_id,
      document_type: to_string(document_type),
      document_id: document_id,
      status: "failed",
      error_message: error_message
    }

    changeset =
      %GeneratedDocument{}
      |> Ecto.Changeset.change(attrs)

    Repo.insert(
      changeset,
      on_conflict: [
        set: [
          status: "failed",
          error_message: error_message,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: [:document_type, :document_id]
    )

    :ok
  end
end
