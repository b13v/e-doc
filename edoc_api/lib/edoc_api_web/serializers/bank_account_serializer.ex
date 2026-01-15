defmodule EdocApiWeb.Serializers.BankAccountSerializer do
  def to_map(a) do
    %{
      id: a.id,
      label: a.label,
      iban: a.iban,
      is_default: a.is_default,
      bank: a.bank && %{id: a.bank.id, name: a.bank.name, bic: a.bank.bic},
      kbe: a.kbe_code && %{id: a.kbe_code.id, code: a.kbe_code.code},
      knp: a.knp_code && %{id: a.knp_code.id, code: a.knp_code.code}
    }
  end
end
