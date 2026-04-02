defmodule EdocApi.MonetizationTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Monetization
  import EdocApi.TestFixtures

  test "creates a trial subscription lazily on first quota consumption" do
    user = create_user!()
    company = create_company!(user)

    assert {:ok, %{used: 1, limit: 10, remaining: 9}} =
             Monetization.consume_document_quota(
               company.id,
               "invoice",
               Ecto.UUID.generate(),
               "invoice_issued"
             )
  end

  test "rejects quota consumption after limit is exceeded" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "included_document_limit" => 1,
        "included_seat_limit" => 2
      })

    assert {:ok, %{used: 1, limit: 1, remaining: 0}} =
             Monetization.consume_document_quota(
               company.id,
               "invoice",
               Ecto.UUID.generate(),
               "invoice_issued"
             )

    assert {:error, :quota_exceeded, %{used: 1, limit: 1}} =
             Monetization.consume_document_quota(
               company.id,
               "invoice",
               Ecto.UUID.generate(),
               "invoice_issued"
             )
  end

  test "effective seat limit includes add-on seats" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "starter",
        "included_document_limit" => 50,
        "included_seat_limit" => 2,
        "add_on_seat_quantity" => 3
      })

    assert Monetization.effective_seat_limit(company.id) == 5
  end

  test "subscription_snapshot reports plan, usage, and seat counts" do
    user = create_user!()
    company = create_company!(user)

    {:ok, _sub} =
      Monetization.activate_subscription_for_company(company.id, %{
        "plan" => "basic",
        "included_document_limit" => 500,
        "included_seat_limit" => 5,
        "add_on_seat_quantity" => 2
      })

    assert {:ok, %{used: 1, limit: 500, remaining: 499}} =
             Monetization.consume_document_quota(
               company.id,
               "invoice",
               Ecto.UUID.generate(),
               "invoice_issued"
             )

    assert %{
             plan: "basic",
             documents_used: 1,
             document_limit: 500,
             seats_used: 1,
             seat_limit: 7
           } = Monetization.subscription_snapshot(company.id)
  end
end
