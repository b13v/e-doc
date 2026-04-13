defmodule EdocApi.Documents.PdfRequestsTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Documents.GeneratedDocument
  alias EdocApi.Documents.PdfRequests
  alias EdocApi.Repo
  alias EdocApi.TestFixtures

  describe "fetch_or_enqueue/5" do
    test "returns cached pdf without enqueueing" do
      user = TestFixtures.create_user!()
      document_id = Ecto.UUID.generate()

      Repo.insert!(%GeneratedDocument{
        user_id: user.id,
        document_type: "invoice",
        document_id: document_id,
        status: "completed",
        pdf_binary: "%PDF-cached"
      })

      enqueue_fun = fn _type, _doc_id, _user_id, _html ->
        send(self(), :enqueued)
        {:ok, :job}
      end

      assert {:ok, "%PDF-cached"} =
               PdfRequests.fetch_or_enqueue("invoice", document_id, user.id, "<html/>",
                 enqueue_fun: enqueue_fun
               )

      refute_received :enqueued
    end

    test "returns cached pdf for another user without enqueueing" do
      owner = TestFixtures.create_user!()
      other_user = TestFixtures.create_user!()
      document_id = Ecto.UUID.generate()

      Repo.insert!(%GeneratedDocument{
        user_id: owner.id,
        document_type: "invoice",
        document_id: document_id,
        status: "completed",
        pdf_binary: "%PDF-cached"
      })

      enqueue_fun = fn _type, _doc_id, _user_id, _html ->
        send(self(), :enqueued)
        {:ok, :job}
      end

      assert {:ok, "%PDF-cached"} =
               PdfRequests.fetch_or_enqueue("invoice", document_id, other_user.id, "<html/>",
                 enqueue_fun: enqueue_fun
               )

      refute_received :enqueued
    end

    test "enqueues when cache is missing and marks status pending" do
      user = TestFixtures.create_user!()
      document_id = Ecto.UUID.generate()

      enqueue_fun = fn _type, _doc_id, _user_id, _html ->
        send(self(), :enqueued)
        {:ok, :job}
      end

      assert {:pending, :enqueued} =
               PdfRequests.fetch_or_enqueue("invoice", document_id, user.id, "<html/>",
                 enqueue_fun: enqueue_fun
               )

      assert_received :enqueued

      assert %GeneratedDocument{status: "pending"} =
               Repo.get_by(GeneratedDocument,
                 user_id: user.id,
                 document_type: "invoice",
                 document_id: document_id
               )
    end

    test "does not enqueue again when document is already pending" do
      user = TestFixtures.create_user!()
      document_id = Ecto.UUID.generate()

      Repo.insert!(%GeneratedDocument{
        user_id: user.id,
        document_type: "invoice",
        document_id: document_id,
        status: "pending"
      })

      enqueue_fun = fn _type, _doc_id, _user_id, _html ->
        send(self(), :enqueued)
        {:ok, :job}
      end

      assert {:pending, :already_queued} =
               PdfRequests.fetch_or_enqueue("invoice", document_id, user.id, "<html/>",
                 enqueue_fun: enqueue_fun
               )

      refute_received :enqueued
    end

    test "enqueues only once across repeated calls for the same document" do
      user = TestFixtures.create_user!()
      document_id = Ecto.UUID.generate()

      enqueue_fun = fn _type, _doc_id, _user_id, _html ->
        send(self(), :enqueued)
        {:ok, :job}
      end

      assert {:pending, :enqueued} =
               PdfRequests.fetch_or_enqueue("invoice", document_id, user.id, "<html/>",
                 enqueue_fun: enqueue_fun
               )

      assert {:pending, :already_queued} =
               PdfRequests.fetch_or_enqueue("invoice", document_id, user.id, "<html/>",
                 enqueue_fun: enqueue_fun
               )

      assert_received :enqueued
      refute_received :enqueued
    end

    test "does not crash when another user requests the same document while pending" do
      user_1 = TestFixtures.create_user!()
      user_2 = TestFixtures.create_user!()
      document_id = Ecto.UUID.generate()

      enqueue_fun = fn _type, _doc_id, _user_id, _html ->
        send(self(), :enqueued)
        {:ok, :job}
      end

      assert {:pending, :enqueued} =
               PdfRequests.fetch_or_enqueue("invoice", document_id, user_1.id, "<html/>",
                 enqueue_fun: enqueue_fun
               )

      assert {:pending, :already_queued} =
               PdfRequests.fetch_or_enqueue("invoice", document_id, user_2.id, "<html/>",
                 enqueue_fun: enqueue_fun
               )

      assert_received :enqueued
      refute_received :enqueued
    end
  end
end
