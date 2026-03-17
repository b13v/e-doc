defmodule EdocApi.OpenAPI do
  @moduledoc false

  @public_operations MapSet.new([
                       {"GET", "/v1/health"},
                       {"GET", "/v1/auth/verify"},
                       {"POST", "/v1/auth/resend-verification"},
                       {"POST", "/v1/auth/signup"},
                       {"POST", "/v1/auth/login"},
                       {"POST", "/v1/auth/refresh"}
                     ])

  def spec do
    paths =
      EdocApiWeb.Router
      |> Phoenix.Router.routes()
      |> Enum.filter(&String.starts_with?(&1.path, "/v1"))
      |> Enum.reduce(%{}, &put_route_operation/2)

    %{
      "openapi" => "3.0.3",
      "info" => %{
        "title" => "Edoc API",
        "version" => "v1",
        "description" =>
          "Generated from Phoenix router. See plans/api_versioning_and_deprecation_policy.md for lifecycle policy."
      },
      "servers" => [%{"url" => "/"}],
      "paths" => paths,
      "components" => %{
        "securitySchemes" => %{
          "bearerAuth" => %{
            "type" => "http",
            "scheme" => "bearer",
            "bearerFormat" => "JWT"
          }
        }
      }
    }
  end

  def write!(output_path \\ default_output_path()) do
    output_dir = Path.dirname(output_path)
    File.mkdir_p!(output_dir)

    spec()
    |> Jason.encode!(pretty: true)
    |> then(&File.write!(output_path, &1 <> "\n"))

    output_path
  end

  def default_output_path do
    Path.join([File.cwd!(), "priv", "static", "openapi", "v1.json"])
  end

  defp put_route_operation(route, paths) do
    path = normalize_path(route.path)
    method = route.verb |> to_string() |> String.downcase()

    operation = %{
      "operationId" => operation_id(route),
      "summary" => summary(route),
      "tags" => [tag_for_path(path)],
      "responses" => response_map(route.verb)
    }

    operation = maybe_put_security(operation, route)

    Map.update(paths, path, %{method => operation}, fn existing ->
      Map.put(existing, method, operation)
    end)
  end

  defp maybe_put_security(operation, route) do
    verb = route.verb |> to_string() |> String.upcase()
    key = {verb, route.path}

    if MapSet.member?(@public_operations, key) do
      operation
    else
      Map.put(operation, "security", [%{"bearerAuth" => []}])
    end
  end

  defp response_map(:post), do: %{"200" => ok_response()}
  defp response_map(:put), do: %{"200" => ok_response()}
  defp response_map(:patch), do: %{"200" => ok_response()}
  defp response_map(:delete), do: %{"200" => ok_response()}
  defp response_map(_), do: %{"200" => ok_response()}

  defp ok_response do
    %{"description" => "Successful response"}
  end

  defp normalize_path(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.map_join("/", fn
      <<":", rest::binary>> -> "{" <> rest <> "}"
      segment -> segment
    end)
    |> then(&("/" <> &1))
  end

  defp operation_id(route) do
    method = route.verb |> to_string() |> String.downcase()

    route.path
    |> String.split("/", trim: true)
    |> Enum.map(fn
      <<":", rest::binary>> -> "by_" <> rest
      segment -> segment
    end)
    |> Enum.join("_")
    |> then(&"#{method}_#{&1}")
  end

  defp summary(route) do
    method = route.verb |> to_string() |> String.upcase()
    "#{method} #{route.path}"
  end

  defp tag_for_path(path) do
    case String.split(path, "/", trim: true) do
      ["v1", resource | _] -> resource
      _ -> "default"
    end
  end
end
