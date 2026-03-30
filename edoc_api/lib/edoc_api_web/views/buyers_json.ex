defmodule EdocApiWeb.BuyersJSON do
  defdelegate index(assigns), to: EdocApiWeb.BuyerJSON
  defdelegate show(assigns), to: EdocApiWeb.BuyerJSON
end
