defmodule EdocApiWeb.PDFEncoder do
  @behaviour Phoenix.Template.Encoder

  def encode_to_iodata(content, _opts) do
    {:ok, content}
  end
end
