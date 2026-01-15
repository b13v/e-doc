defmodule EdocApi.Core do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Core.Company
  alias EdocApi.Core.Invoice
  alias EdocApi.Core.InvoiceItem
  alias EdocApi.Core.InvoiceCounter
  alias EdocApi.Core.{Bank, KbeCode, KnpCode}
  alias EdocApi.Core.CompanyBankAccount

  # ----- Companies--------
  def get_company_by_user_id(user_id) when is_binary(user_id) do
    Repo.get_by(Company, user_id: user_id)
  end

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

  # ----- Company bank accounts -----
  def list_company_bank_accounts_for_user(user_id) do
    case get_company_by_user_id(user_id) do
      nil ->
        []

      company ->
        CompanyBankAccount
        |> where([a], a.company_id == ^company.id)
        |> order_by([a], desc: a.is_default, asc: a.label)
        |> Repo.all()
        |> Repo.preload([:bank, :kbe_code, :knp_code])
    end
  end

  def create_company_bank_account_for_user(user_id, attrs) do
    case get_company_by_user_id(user_id) do
      nil ->
        {:error, :company_required}

      company ->
        %CompanyBankAccount{}
        |> CompanyBankAccount.changeset(attrs, company.id)
        |> Repo.insert()
        |> case do
          {:ok, acc} -> {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}
          {:error, cs} -> {:error, cs}
        end
    end
  end

  # ----- Invoices--------
  def get_invoice_for_user(user_id, invoice_id) do
    Invoice
    |> where([i], i.id == ^invoice_id and i.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> nil
      invoice -> preload_invoice(invoice)
    end
  end

  def list_invoices_for_user(user_id) do
    Invoice
    |> where([i], i.user_id == ^user_id)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
    |> Repo.preload([:items, company: [:bank, :kbe_code, :knp_code]])
  end

  def issue_invoice_for_user(user_id, invoice_id) do
    invoice =
      Invoice
      |> where([i], i.user_id == ^user_id and i.id == ^invoice_id)
      |> Repo.one()
      |> case do
        nil -> nil
        inv -> preload_invoice(inv)
      end

    mark_invoice_issued(invoice)
  end

  def create_invoice_for_user(user_id, company_id, attrs) do
    items_attrs = Map.get(attrs, "items") || Map.get(attrs, :items) || []

    Repo.transaction(fn ->
      if items_attrs == [] do
        Repo.rollback({:error, :items_required})
      end

      {prepared_items, subtotal} = prepare_items_and_subtotal!(items_attrs)

      # ✅ AUTONUMBER: если number не передан — генерим только цифры

      raw_number = Map.get(attrs, "number") || Map.get(attrs, :number)

      number =
        cond do
          is_nil(raw_number) ->
            next_invoice_number!(company_id)

          is_binary(raw_number) and String.trim(raw_number) == "" ->
            next_invoice_number!(company_id)

          true ->
            raw_number
        end

      # ---- SELLER from Company-----
      company = Repo.get!(Company, company_id)

      seller_attrs = %{
        "seller_name" => company.name,
        "seller_bin_iin" => company.bin_iin,
        "seller_address" => format_company_address(company),
        "seller_iban" => company.iban
      }

      invoice_attrs =
        attrs
        |> Map.drop(["items", :items, "subtotal", :subtotal, "vat", :vat, "total", :total])
        |> Map.merge(seller_attrs)
        |> Map.put("subtotal", subtotal)
        |> Map.put("number", number)

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

  defp preload_invoice(invoice) do
    Repo.preload(invoice, [:items, company: [:bank, :kbe_code, :knp_code]])
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

  defp format_company_address(%Company{} = c) do
    city = (c.city || "") |> String.trim()
    addr = (c.address || "") |> String.trim()

    cond do
      city != "" and addr != "" -> "г. #{city}, #{addr}"
      addr != "" -> addr
      city != "" -> "г. #{city}"
      true -> ""
    end
  end

  # -----InvoiceCounter-------------
  def next_invoice_number!(company_id) do
    Repo.transaction(fn ->
      # Atomic upsert: insert starts at 2, conflicts increment by 1.
      # Returned next_seq is the "next" value, so seq = next_seq - 1.
      %{next_seq: next_seq} =
        Repo.insert!(
          %InvoiceCounter{company_id: company_id, next_seq: 2},
          on_conflict: [inc: [next_seq: 1]],
          conflict_target: :company_id,
          returning: [:next_seq]
        )

      seq = next_seq - 1

      # формат: только цифры с ведущими нулями
      String.pad_leading(Integer.to_string(seq), 10, "0")
    end)
    |> case do
      {:ok, number} -> number
      {:error, reason} -> raise "invoice number generation failed: #{inspect(reason)}"
    end
  end

  # ------------ Marking-Invoice-issued-------------------

  def mark_invoice_issued(invoice) do
    invoice =
      case invoice do
        nil -> nil
        inv -> Repo.preload(inv, [:items, :company])
      end

    cond do
      is_nil(invoice) ->
        {:error, :invoice_not_found}

      invoice.status == "issued" ->
        {:error, :already_issued}

      invoice.status != "draft" ->
        {:error, :cannot_issue, %{status: "must be draft to issue"}}

      (invoice.items || []) == [] ->
        {:error, :cannot_issue, %{items: "must have at least 1 item"}}

      is_nil(invoice.total) or Decimal.compare(invoice.total, Decimal.new("0.00")) != :gt ->
        {:error, :cannot_issue, %{total: "must be > 0"}}

      true ->
        invoice
        |> Ecto.Changeset.change(status: "issued")
        |> Repo.update()
        |> case do
          {:ok, inv} -> {:ok, Repo.preload(inv, [:items, :company])}
          {:error, cs} -> {:error, cs}
        end
    end
  end

  # ----- Dicts -----
  def list_banks do
    Bank |> order_by([b], asc: b.name) |> Repo.all()
  end

  def list_kbe_codes do
    KbeCode |> order_by([k], asc: k.code) |> Repo.all()
  end

  def list_knp_codes do
    KnpCode |> order_by([k], asc: k.code) |> Repo.all()
  end
end
