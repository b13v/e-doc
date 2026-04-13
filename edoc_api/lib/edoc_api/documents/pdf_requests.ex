defmodule EdocApi.Documents.PdfRequests do
  @moduledoc """
  Coordinates cache-first PDF retrieval with async background generation.
  """
  import Ecto.Query, warn: false

  alias EdocApi.Documents.GeneratedDocument
  alias EdocApi.ObanWorkers.PdfGenerationWorker
  alias EdocApi.Repo

  @type document_type :: :invoice | :contract | :act | binary()

  @spec fetch_or_enqueue(document_type(), Ecto.UUID.t(), Ecto.UUID.t(), binary(), keyword()) ::
          {:ok, binary()}
          | {:pending, :enqueued | :already_queued}
          | {:error, term()}
  def fetch_or_enqueue(document_type, document_id, user_id, html_binary, opts \\ [])
      when is_binary(document_id) and is_binary(user_id) and is_binary(html_binary) do
    normalized_type = normalize_type(document_type)
    worker = Keyword.get(opts, :worker, PdfGenerationWorker)
    enqueue_fun = Keyword.get(opts, :enqueue_fun, &worker.enqueue/4)

    case worker.get_pdf(normalized_type, document_id, user_id) do
      {:ok, pdf_binary} ->
        {:ok, pdf_binary}

      {:error, :not_found} ->
        ensure_pending_and_enqueue(
          normalized_type,
          document_id,
          user_id,
          html_binary,
          enqueue_fun
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec status(document_type(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, :pending | :processing | :completed | :failed} | {:error, :not_found}
  def status(document_type, document_id, user_id)
      when is_binary(document_id) and is_binary(user_id) do
    normalized_type = normalize_type(document_type)

    case get_generated_document(normalized_type, document_id) do
      nil -> {:error, :not_found}
      %GeneratedDocument{status: status} -> {:ok, String.to_existing_atom(status)}
    end
  rescue
    ArgumentError ->
      {:error, :not_found}
  end

  defp ensure_pending_and_enqueue(document_type, document_id, user_id, html_binary, enqueue_fun) do
    case get_generated_document(document_type, document_id) do
      %GeneratedDocument{status: "completed", pdf_binary: pdf_binary}
      when is_binary(pdf_binary) ->
        {:ok, pdf_binary}

      %GeneratedDocument{status: status} when status in ["pending", "processing"] ->
        {:pending, :already_queued}

      %GeneratedDocument{} = generated ->
        {:ok, _} =
          generated
          |> Ecto.Changeset.change(status: "pending", error_message: nil)
          |> Repo.update()

        do_enqueue(document_type, document_id, user_id, html_binary, enqueue_fun)

      nil ->
        case Repo.insert(
               GeneratedDocument.changeset(%GeneratedDocument{}, %{
                 user_id: user_id,
                 document_type: document_type,
                 document_id: document_id,
                 status: "pending"
               })
             ) do
          {:ok, _generated_document} ->
            do_enqueue(document_type, document_id, user_id, html_binary, enqueue_fun)

          {:error, changeset} ->
            case get_generated_document(document_type, document_id) do
              %GeneratedDocument{status: "completed", pdf_binary: pdf_binary}
              when is_binary(pdf_binary) ->
                {:ok, pdf_binary}

              %GeneratedDocument{status: status} when status in ["pending", "processing"] ->
                {:pending, :already_queued}

              %GeneratedDocument{} ->
                {:pending, :already_queued}

              nil ->
                {:error, changeset}
            end
        end
    end
  end

  defp do_enqueue(document_type, document_id, user_id, html_binary, enqueue_fun) do
    case enqueue_fun.(document_type, document_id, user_id, html_binary) do
      {:ok, _job} -> {:pending, :enqueued}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_generated_document(document_type, document_id) do
    GeneratedDocument
    |> where(
      [g],
      g.document_type == ^document_type and g.document_id == ^document_id
    )
    |> limit(1)
    |> Repo.one()
  end

  defp normalize_type(type) when type in [:invoice, :contract, :act], do: Atom.to_string(type)
  defp normalize_type(type) when type in ["invoice", "contract", "act"], do: type
end
