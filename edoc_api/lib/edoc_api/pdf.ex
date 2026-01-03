defmodule EdocApi.Pdf do
  @moduledoc false

  @spec html_to_pdf(binary()) :: {:ok, binary()} | {:error, term()}
  def html_to_pdf(html) when is_binary(html) do
    tmp_dir = System.tmp_dir!()
    uniq = Integer.to_string(System.unique_integer([:positive]))

    html_path = Path.join(tmp_dir, "edoc_#{uniq}.html")
    pdf_path = Path.join(tmp_dir, "edoc_#{uniq}.pdf")

    File.write!(html_path, html)

    args = ["--encoding", "utf-8", "--quiet", html_path, pdf_path]

    case System.cmd("wkhtmltopdf", args, stderr_to_stdout: true) do
      {_out, 0} ->
        pdf = File.read!(pdf_path)
        cleanup([html_path, pdf_path])
        {:ok, pdf}

      {out, code} ->
        cleanup([html_path, pdf_path])
        {:error, {:wkhtmltopdf_failed, code, out}}
    end
  rescue
    e -> {:error, e}
  end

  defp cleanup(paths), do: Enum.each(paths, &File.rm/1)
end
