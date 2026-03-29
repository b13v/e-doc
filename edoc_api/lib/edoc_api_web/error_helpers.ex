defmodule EdocApiWeb.ErrorHelpers do
  @moduledoc false

  use Gettext, backend: EdocApiWeb.Gettext

  @field_labels %{
    address: "Address",
    bank_account_id: "Bank account",
    bank_id: "Bank",
    basis: "Basis",
    bin_iin: "BIN/IIN",
    buyer_address: "Buyer address",
    buyer_id: "Buyer",
    city: "City",
    company_id: "Company",
    contract_id: "Contract",
    currency: "Currency",
    director_name: "Director name",
    director_title: "Director title",
    due_date: "Due date",
    email: "Email",
    iban: "IBAN",
    issue_date: "Issue date",
    kbe_code_id: "KBE code",
    knp_code_id: "KNP code",
    label: "Label",
    legal_form: "Legal form",
    name: "Name",
    number: "Number",
    phone: "Phone",
    representative_name: "Representative name",
    representative_title: "Representative title",
    service_name: "Service name",
    status: "Status",
    total: "Total",
    subtotal: "Subtotal",
    unit_price: "Unit price",
    qty: "Quantity",
    actual_date: "Actual date",
    vat: "VAT",
    vat_rate: "VAT rate"
  }

  def format_changeset_errors(changeset) do
    changeset
    |> translate_errors()
    |> Enum.map(fn {field, errors} ->
      "#{field_label(field)}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end

  def translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  end

  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(EdocApiWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(EdocApiWeb.Gettext, "errors", msg, opts)
    end
  end

  def field_label(field) when is_atom(field) do
    Gettext.gettext(EdocApiWeb.Gettext, Map.get(@field_labels, field, Phoenix.Naming.humanize(field)))
  end

  def field_label(field), do: field
end
