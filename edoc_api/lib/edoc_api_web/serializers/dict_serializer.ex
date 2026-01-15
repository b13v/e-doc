defmodule EdocApiWeb.Serializers.DictSerializer do
  def bank_to_map(b), do: %{id: b.id, name: b.name, bic: b.bic}
  def code_to_map(c), do: %{id: c.id, code: c.code, description: c.description}
end
