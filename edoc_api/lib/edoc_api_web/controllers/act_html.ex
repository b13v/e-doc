defmodule EdocApiWeb.ActHTML do
  use EdocApiWeb, :html

  embed_templates("act_html/*")

  def fmt_date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")
  def fmt_date(_), do: "—"

  def act_row_actions(act) do
    primary = %{
      label: gettext("View"),
      tone: :info,
      transport: :link,
      method: :get,
      href: "/acts/#{act.id}"
    }

    secondary =
      sign_action(act) ++ draft_edit_or_pdf_action(act) ++ delete_action(act)

    %{primary: primary, secondary: secondary}
  end

  defp sign_action(%{status: "issued"} = act) do
    [
      %{
        label: gettext("Signed"),
        tone: :success,
        transport: :form,
        method: :post,
        action: "/acts/#{act.id}/sign",
        confirm_text: gettext("Mark this act as signed?")
      }
    ]
  end

  defp sign_action(_act), do: []

  defp draft_edit_or_pdf_action(%{status: "draft"} = act) do
    [
      %{
        label: gettext("Edit"),
        tone: :success,
        transport: :link,
        method: :get,
        href: "/acts/#{act.id}/edit"
      }
    ]
  end

  defp draft_edit_or_pdf_action(act) do
    [
      %{
        label: gettext("PDF"),
        transport: :link,
        method: :get,
        href: "/acts/#{act.id}/pdf"
      }
    ]
  end

  defp delete_action(%{status: "draft"} = act) do
    [
      %{
        label: gettext("Delete"),
        tone: :danger,
        transport: :form,
        method: :post,
        action: "/acts/#{act.id}",
        _method: "delete",
        confirm_text: gettext("Delete this act?")
      }
    ]
  end

  defp delete_action(_act), do: []
end
