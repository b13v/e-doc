defmodule EdocApiWeb.ActHTML do
  use EdocApiWeb, :html

  embed_templates("act_html/*")

  def fmt_date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")
  def fmt_date(_), do: "—"
end
