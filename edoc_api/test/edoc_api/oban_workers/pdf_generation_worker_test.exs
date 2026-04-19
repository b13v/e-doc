defmodule EdocApi.ObanWorkers.PdfGenerationWorkerTest do
  use EdocApi.DataCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Documents.GeneratedDocument
  alias EdocApi.ObanWorkers.PdfGenerationWorker
  alias EdocApi.Repo

  test "allows complex pdf generation jobs to run for two minutes" do
    assert PdfGenerationWorker.timeout(%Oban.Job{}) == :timer.minutes(2)
  end

  test "cancels missing document jobs instead of retrying them" do
    user = create_user!()
    document_id = Ecto.UUID.generate()

    job = %Oban.Job{
      args: %{
        "document_type" => "invoice",
        "document_id" => document_id,
        "user_id" => user.id
      }
    }

    assert PdfGenerationWorker.perform(job) == {:cancel, "Document not found"}

    assert %GeneratedDocument{
             status: "failed",
             error_message: "Document not found",
             document_type: "invoice",
             document_id: ^document_id
           } =
             Repo.get_by(GeneratedDocument,
               document_type: "invoice",
               document_id: document_id
             )
  end
end
