defmodule EdocApiWeb.PDFEncoder do
  @moduledoc """
  PDF encoder for Phoenix template rendering.
  """

  @doc """
  Returns PDF content as iodata for Phoenix response.
  """
  def encode_to_iodata(content, _opts) do
    {:ok, content}
  end
end
