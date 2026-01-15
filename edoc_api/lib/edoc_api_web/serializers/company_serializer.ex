defmodule EdocApiWeb.Serializers.CompanySerializer do
  def to_map(company) do
    %{
      id: company.id,
      name: company.name,
      legal_form: company.legal_form,
      bin_iin: company.bin_iin,
      city: company.city,
      address: company.address,
      bank_name: company.bank_name,
      iban: company.iban,
      email: company.email,
      phone: company.phone,
      representative_name: company.representative_name,
      representative_title: company.representative_title,
      basis: company.basis,
      bank_id: company.bank_id,
      kbe_code_id: company.kbe_code_id,
      knp_code_id: company.knp_code_id,
      inserted_at: company.inserted_at,
      updated_at: company.updated_at
    }
  end
end
