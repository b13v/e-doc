defmodule EdocApi.OpenAPITest do
  use ExUnit.Case, async: true

  test "builds v1 OpenAPI spec with auth and public operations" do
    spec = EdocApi.OpenAPI.spec()

    assert spec["openapi"] == "3.0.3"
    assert is_map(spec["paths"])

    assert get_in(spec, ["paths", "/v1/auth/login", "post", "responses", "200"]) != nil

    refute Map.has_key?(
             get_in(spec, ["paths", "/v1/auth/login", "post"]),
             "security"
           )

    assert get_in(spec, ["paths", "/v1/company", "get", "security"]) == [%{"bearerAuth" => []}]
  end
end
