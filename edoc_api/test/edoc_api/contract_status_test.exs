defmodule EdocApi.ContractStatusTest do
  use ExUnit.Case, async: true

  alias EdocApi.ContractStatus

  test "default is draft and can issue only in draft" do
    assert ContractStatus.default() == "draft"
    assert ContractStatus.can_issue?(%{status: "draft"})
    refute ContractStatus.can_issue?(%{status: "issued"})
  end
end
