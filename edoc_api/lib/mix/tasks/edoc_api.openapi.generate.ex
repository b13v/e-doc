defmodule Mix.Tasks.EdocApi.Openapi.Generate do
  use Mix.Task

  @shortdoc "Generates OpenAPI JSON from router"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [output: :string])

    output_path = Keyword.get(opts, :output, EdocApi.OpenAPI.default_output_path())
    path = EdocApi.OpenAPI.write!(output_path)

    Mix.shell().info("OpenAPI spec generated: #{path}")
  end
end
