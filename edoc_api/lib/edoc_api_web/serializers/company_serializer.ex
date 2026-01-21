defmodule EdocApiWeb.Serializers.CompanySerializer do
  @moduledoc """
  Serializer for Company resources.

  NOTE: bank_name, iban, bank_id, kbe_code_id, knp_code_id are deprecated.
  Use the /company/bank-accounts endpoint to manage bank accounts instead.
  """

  def to_map(company) do
    base_map = %{
      id: company.id,
      name: company.name,
      legal_form: company.legal_form,
      bin_iin: company.bin_iin,
      city: company.city,
      address: company.address,
      email: company.email,
      phone: company.phone,
      representative_name: company.representative_name,
      representative_title: company.representative_title,
      basis: company.basis,
      inserted_at: company.inserted_at,
      updated_at: company.updated_at
    }

    # Include deprecated fields only if they exist (for backward compatibility during migration)
    base_map
    |> maybe_add_deprecated_field(company, :bank_name)
    |> maybe_add_deprecated_field(company, :iban)
    |> maybe_add_deprecated_field(company, :bank_id)
    |> maybe_add_deprecated_field(company, :kbe_code_id)
    |> maybe_add_deprecated_field(company, :knp_code_id)
  end

  defp maybe_add_deprecated_field(map, company, field) do
    value = Map.get(company, field)

    if value && value != "" do
      Map.put(map, field, value)
    else
      map
    end
  end
end
