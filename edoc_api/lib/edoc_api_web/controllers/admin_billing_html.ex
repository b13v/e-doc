defmodule EdocApiWeb.AdminBillingHTML do
  use EdocApiWeb, :html

  alias EdocApi.LegalForms

  embed_templates("admin_billing_html/*")

  def plan_label(nil), do: "No plan"
  def plan_label(%{name: name}), do: name

  def value_or_dash(nil), do: "-"
  def value_or_dash(value), do: value

  def invoice_plan_label(%{plan_snapshot_code: code}) when is_binary(code) do
    code
    |> String.capitalize()
  end

  def invoice_plan_label(_), do: "-"

  def invoice_virtual?(%{virtual?: true}), do: true
  def invoice_virtual?(_), do: false

  def date_or_dash(nil), do: "-"

  def date_or_dash(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%d.%m.%Y")
  end

  def membership_email(%{invite_email: email}) when is_binary(email), do: email
  def membership_email(%{user: %{email: email}}), do: email
  def membership_email(_), do: "-"

  def company_display_name(%{name: name} = company) when is_binary(name) do
    "#{legal_form_short(Map.get(company, :legal_form))} #{name}"
  end

  def company_display_name(_), do: "-"

  def metadata_note(%{metadata: %{"note" => note}}), do: note
  def metadata_note(%{metadata: %{note: note}}), do: note
  def metadata_note(_), do: ""

  defp legal_form_short(legal_form) do
    case LegalForms.display(legal_form) do
      "Товарищество с ограниченной ответственностью" -> "ТОО"
      "Акционерное общество" -> "АО"
      "Индивидуальный предприниматель" -> "ИП"
      _ -> "ТОО"
    end
  end
end
