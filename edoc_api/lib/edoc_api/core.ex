defmodule EdocApi.Core do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Core.Company
  alias EdocApi.Core.Invoice
  alias EdocApi.Core.InvoiceItem

  # ----- Companies--------
  def get_company_by_user_id(user_id) when is_binary(user_id) do
    Repo.get_by(Company, user_id: user_id)
  end

  # def upsert_company_for_user(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
  #   case get_company_by_user_id(user_id) do
  #     nil ->
  #       %Company{}
  #       |> Company.changeset(attrs, user_id)
  #       |> Repo.insert()

  #     %Company{} = company ->
  #       company
  #       |> Company.changeset(attrs, user_id)
  #       |> Repo.update()
  #   end
  # end

  def upsert_company_for_user(user_id, attrs) do
    company = get_company_by_user_id(user_id) || %Company{}

    changeset = Company.changeset(company, attrs, user_id)
    warnings = Company.warnings_from_changeset(changeset)

    case Repo.insert_or_update(changeset) do
      {:ok, company} ->
        {:ok, company, warnings}

      {:error, changeset} ->
        # тут будут настоящие ошибки (не warnings)
        {:error, changeset, Company.warnings_from_changeset(changeset)}
    end
  end

  # ----- Invoices--------
  # def get_invoice_for_user(user_id, invoice_id)
  #     when is_binary(user_id) and is_binary(invoice_id) do
  #   Repo.get_by(Invoice, id: invoice_id, user_id: user_id)
  # end

  # def get_invoice_for_user(user_id, invoice_id)
  #     when is_binary(user_id) and is_binary(invoice_id) do
  #   Invoice
  #   |> where([i], i.id == ^invoice_id and i.user_id == ^user_id)
  #   |> preload([:company, :items])
  #   |> Repo.one()
  # end
  def get_invoice_for_user(user_id, invoice_id) do
    Invoice
    |> where([i], i.id == ^invoice_id and i.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> nil
      invoice -> Repo.preload(invoice, [:items, :company])
    end
  end

  def list_invoices_for_user(user_id) do
    Invoice
    |> where([i], i.user_id == ^user_id)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
    |> Repo.preload([:items, :company])
  end

  # def create_invoice_for_user(user_id, company_id, attrs)
  #     when is_binary(user_id) and is_binary(company_id) and is_map(attrs) do
  #   %Invoice{}
  #   |> Invoice.changeset(attrs, user_id, company_id)
  #   |> Repo.insert()
  # end

  def create_invoice_for_user(user_id, company_id, attrs) do
    items_attrs = Map.get(attrs, "items") || Map.get(attrs, :items) || []

    Repo.transaction(fn ->
      if items_attrs == [] do
        Repo.rollback({:error, :items_required})
      end

      {prepared_items, subtotal} = prepare_items_and_subtotal!(items_attrs)

      invoice_attrs =
        attrs
        |> Map.drop(["items", :items, "subtotal", :subtotal, "vat", :vat, "total", :total])
        |> Map.put("subtotal", subtotal)

      invoice_changeset = Invoice.changeset(%Invoice{}, invoice_attrs, user_id, company_id)

      invoice =
        case Repo.insert(invoice_changeset) do
          {:ok, inv} -> inv
          {:error, cs} -> Repo.rollback({:error, cs})
        end

      prepared_items
      |> Enum.each(fn item_attrs ->
        cs =
          %InvoiceItem{}
          |> InvoiceItem.changeset(Map.put(item_attrs, "invoice_id", invoice.id))

        case Repo.insert(cs) do
          {:ok, _} -> :ok
          {:error, cs} -> Repo.rollback({:error, cs})
        end
      end)

      Repo.preload(invoice, [:items, :company])
    end)
    |> case do
      {:ok, invoice} -> {:ok, invoice}
      {:error, {:error, :items_required}} -> {:error, :items_required}
      {:error, {:error, %Ecto.Changeset{} = cs}} -> {:error, cs}
      {:error, other} -> {:error, other}
    end
  end

  defp prepare_items_and_subtotal!(items_attrs) when is_list(items_attrs) do
    {items, subtotal} =
      Enum.reduce(items_attrs, {[], Decimal.new("0.00")}, fn raw, {acc, sum} ->
        m = normalize_map_keys(raw)

        qty = parse_int(Map.get(m, "qty", 1))
        unit_price = parse_decimal(Map.get(m, "unit_price"))

        amount =
          unit_price
          |> Decimal.mult(Decimal.new(qty))
          |> Decimal.round(2)

        item = %{
          "code" => Map.get(m, "code"),
          "name" => Map.get(m, "name"),
          "qty" => qty,
          "unit_price" => unit_price,
          "amount" => amount
        }

        {[item | acc], Decimal.add(sum, amount)}
      end)

    {Enum.reverse(items), Decimal.round(subtotal, 2)}
  end

  defp normalize_map_keys(map) when is_map(map) do
    # поддержка atom keys и string keys
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> n
      _ -> 1
    end
  end

  defp parse_int(_), do: 1

  defp parse_decimal(%Decimal{} = d), do: d
  defp parse_decimal(v) when is_integer(v), do: Decimal.new(v)

  defp parse_decimal(v) when is_float(v),
    do: v |> :erlang.float_to_binary(decimals: 2) |> Decimal.new()

  defp parse_decimal(v) when is_binary(v) do
    v =
      v
      |> String.trim()
      |> String.replace(" ", "")
      # на случай "100 000,00"
      |> String.replace(",", ".")

    case Decimal.parse(v) do
      {d, ""} -> d
      _ -> Decimal.new("0.00")
    end
  end

  defp parse_decimal(_), do: Decimal.new("0.00")
end
