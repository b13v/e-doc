defmodule EdocApi.Core.ContractChangesetTest do
  use EdocApi.DataCase, async: true

  alias EdocApi.Core.Contract

  test "sanitizes body_html on write" do
    company_id = Ecto.UUID.generate()

    changeset =
      Contract.changeset(
        %Contract{},
        %{
          "number" => "C-1",
          "date" => Date.utc_today(),
          "body_html" => "<script>alert('x')</script><p>Safe</p>"
        },
        company_id
      )

    sanitized = changeset.changes.body_html
    refute String.contains?(sanitized, "<script")
    assert String.contains?(sanitized, "<p>Safe</p>")
  end
end
