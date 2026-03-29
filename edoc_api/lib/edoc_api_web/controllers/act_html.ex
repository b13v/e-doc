defmodule EdocApiWeb.ActHTML do
  use EdocApiWeb, :html

  embed_templates("act_html/*")

  def fmt_date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")
  def fmt_date(_), do: "—"

  def act_row_actions(act) do
    primary = %{
      label: gettext("View"),
      transport: :link,
      method: :get,
      href: "/acts/#{act.id}",
      class:
        "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-blue-600 transition hover:bg-blue-50 hover:text-blue-900"
    }

    secondary = [
      %{
        label: gettext("PDF"),
        transport: :link,
        method: :get,
        href: "/acts/#{act.id}/pdf",
        class:
          "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-green-600 transition hover:bg-green-50 hover:text-green-900"
      }
    ] ++ delete_action(act)

    %{primary: primary, secondary: secondary}
  end

  defp delete_action(%{status: "draft"} = act) do
    [
      %{
        label: gettext("Delete"),
        transport: :form,
        method: :post,
        action: "/acts/#{act.id}",
        _method: "delete",
        class:
          "block w-full rounded-xl px-3 py-2 text-left text-sm font-medium text-red-700 transition hover:bg-red-50 hover:text-red-900",
        confirm_text: gettext("Delete this act?")
      }
    ]
  end

  defp delete_action(_act), do: []
end
