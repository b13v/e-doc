defmodule EdocApi.Pdf do
  @moduledoc false

  @default_timeout_ms 60_000

  @spec html_to_pdf(binary()) :: {:ok, binary()} | {:error, term()}
  def html_to_pdf(html) when is_binary(html) do
    html_to_pdf(html, [])
  end

  @spec html_to_pdf(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def html_to_pdf(html, opts) when is_binary(html) and is_list(opts) do
    case System.find_executable("wkhtmltopdf") do
      nil ->
        {:error, :pdf_generation_failed}

      executable ->
        tmp_dir = System.tmp_dir!()
        uniq = Integer.to_string(System.unique_integer([:positive]))

        html_path = Path.join(tmp_dir, "edoc_#{uniq}.html")
        pdf_path = Path.join(tmp_dir, "edoc_#{uniq}.pdf")
        timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

        try do
          with :ok <- File.write(html_path, html),
               {:ok, pdf_binary} <-
                 run_wkhtmltopdf(executable, html_path, pdf_path, opts, timeout_ms) do
            {:ok, pdf_binary}
          else
            _ -> {:error, :pdf_generation_failed}
          end
        rescue
          _ -> {:error, :pdf_generation_failed}
        after
          cleanup([html_path, pdf_path])
        end
    end
  end

  defp run_wkhtmltopdf(executable, html_path, pdf_path, opts, timeout_ms) do
    orientation_args =
      case Keyword.get(opts, :orientation, :portrait) do
        :landscape -> ["--orientation", "Landscape"]
        _ -> []
      end

    args =
      [
        "--encoding",
        "utf-8",
        "--quiet"
      ] ++ orientation_args ++ [html_path, pdf_path]

    task = Task.async(fn -> System.cmd(executable, args, stderr_to_stdout: true) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {_out, 0}} ->
        case File.read(pdf_path) do
          {:ok, pdf_binary} -> {:ok, pdf_binary}
          {:error, _} -> {:error, :pdf_generation_failed}
        end

      {:ok, {_out, _code}} ->
        {:error, :pdf_generation_failed}

      _ ->
        {:error, :pdf_generation_failed}
    end
  end

  defp cleanup(paths), do: Enum.each(paths, &File.rm/1)
end
