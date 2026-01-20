defmodule EdocApi.Invoicing do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Core.Company
  alias EdocApi.Core.Invoice
  alias EdocApi.Core.InvoiceBankSnapshot
  alias EdocApi.Core.InvoiceItem
  alias EdocApi.Core.InvoiceCounter
  alias EdocApi.Core.CompanyBankAccount
  alias EdocApi.InvoiceStatus

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
    |> Repo.preload([
      :items,
      :bank_snapshot,
      :contract,
      bank_account: [:bank, :kbe_code, :knp_code],
      company: [:bank, :kbe_code, :knp_code]
    ])
  end

  def issue_invoice_for_user(user_id, invoice_id) do
    Repo.transaction(fn ->
      invoice =
        Invoice
        |> where([i], i.user_id == ^user_id and i.id == ^invoice_id)
        |> Repo.one()
        |> case do
          nil -> Repo.rollback({:error, :invoice_not_found})
          inv -> preload_invoice(inv)
        end

      case do_issue_invoice(invoice) do
        {:ok, inv} -> inv
        {:error, reason} -> Repo.rollback({:error, reason})
        {:error, reason, details} -> Repo.rollback({:error, reason, details})
      end
    end)
    |> case do
      {:ok, invoice} -> {:ok, invoice}
      {:error, {:error, reason}} -> {:error, reason}
      {:error, {:error, reason, details}} -> {:error, reason, details}
    end
  end

  def create_invoice_for_user(user_id, company_id, attrs) do
    items_attrs = Map.get(attrs, "items") || Map.get(attrs, :items) || []
    bank_account_id = Map.get(attrs, "bank_account_id") || Map.get(attrs, :bank_account_id)

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

      # ---- SELLER from Company / Bank Account -----
      company = Repo.get!(Company, company_id)

      bank_account =
        case bank_account_id do
          nil ->
            nil

          id ->
            case Repo.get(CompanyBankAccount, id) do
              %CompanyBankAccount{company_id: ^company_id} = acc -> acc
              _ -> Repo.rollback({:error, :bank_account_not_found})
            end
        end

      seller_attrs = %{
        "seller_name" => company.name,
        "seller_bin_iin" => company.bin_iin,
        "seller_address" => format_company_address(company),
        "seller_iban" => (bank_account && bank_account.iban) || company.iban
      }

      invoice_attrs =
        attrs
        |> Map.drop(["items", :items, "subtotal", :subtotal, "vat", :vat, "total", :total])
        |> Map.merge(seller_attrs)
        |> Map.put("subtotal", subtotal)
        |> Map.put("number", number)
        |> maybe_put_bank_account_id(bank_account)

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

      preload_invoice(invoice)
    end)
    |> case do
      {:ok, invoice} -> {:ok, invoice}
      {:error, {:error, :items_required}} -> {:error, :items_required}
      {:error, {:error, :bank_account_not_found}} -> {:error, :bank_account_not_found}
      {:error, {:error, %Ecto.Changeset{} = cs}} -> {:error, cs}
      {:error, other} -> {:error, other}
    end
  end

  defp preload_invoice(invoice) do
    Repo.preload(invoice, [
      :items,
      :bank_snapshot,
      :contract,
      bank_account: [:bank, :kbe_code, :knp_code],
      company: [:bank, :kbe_code, :knp_code]
    ])
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

  defp maybe_put_bank_account_id(attrs, nil), do: attrs

  defp maybe_put_bank_account_id(attrs, %CompanyBankAccount{id: id}),
    do: Map.put(attrs, "bank_account_id", id)

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
    Repo.transaction(fn ->
      invoice =
        case invoice do
          nil -> Repo.rollback({:error, :invoice_not_found})
          inv -> preload_invoice(inv)
        end

      case do_issue_invoice(invoice) do
        {:ok, inv} -> inv
        {:error, reason} -> Repo.rollback({:error, reason})
        {:error, reason, details} -> Repo.rollback({:error, reason, details})
      end
    end)
    |> case do
      {:ok, inv} -> {:ok, inv}
      {:error, {:error, reason}} -> {:error, reason}
      {:error, {:error, reason, details}} -> {:error, reason, details}
    end
  end

  defp do_issue_invoice(invoice) do
    cond do
      is_nil(invoice) ->
        {:error, :invoice_not_found}

      not is_nil(invoice.bank_snapshot) ->
        {:error, :already_issued}

      InvoiceStatus.is_issued?(invoice) ->
        {:error, :already_issued}

      not InvoiceStatus.can_issue?(invoice) ->
        {:error, :cannot_issue, %{status: "must be draft to issue"}}

      (invoice.items || []) == [] ->
        {:error, :cannot_issue, %{items: "must have at least 1 item"}}

      is_nil(invoice.total) or Decimal.compare(invoice.total, Decimal.new("0.00")) != :gt ->
        {:error, :cannot_issue, %{total: "must be > 0"}}

      true ->
        with {:ok, bank_account} <- select_bank_account(invoice),
             {:ok, _snap} <- create_bank_snapshot(invoice, bank_account),
             {:ok, inv} <- update_invoice_status(invoice, InvoiceStatus.issued()) do
          {:ok, preload_invoice(inv)}
        end
    end
  end

  defp update_invoice_status(invoice, status) do
    invoice
    |> Ecto.Changeset.change(status: status)
    |> Repo.update()
  end

  defp select_bank_account(invoice) do
    invoice_company_id = invoice.company_id

    case invoice.bank_account do
      %CompanyBankAccount{} = acc ->
        {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}

      _ ->
        case invoice.bank_account_id do
          nil ->
            CompanyBankAccount
            |> where([a], a.company_id == ^invoice_company_id and a.is_default == true)
            |> order_by([a], desc: a.inserted_at)
            |> limit(1)
            |> Repo.one()
            |> case do
              nil -> {:error, :bank_account_required}
              acc -> {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}
            end

          id ->
            case Repo.get(CompanyBankAccount, id) do
              %CompanyBankAccount{company_id: ^invoice_company_id} = acc ->
                {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}

              _ ->
                {:error, :bank_account_not_found}
            end
        end
    end
  end

  defp create_bank_snapshot(invoice, %CompanyBankAccount{} = acc) do
    bank = acc.bank
    kbe = acc.kbe_code
    knp = acc.knp_code

    attrs = %{
      "invoice_id" => invoice.id,
      "bank_name" => bank && bank.name,
      "bic" => bank && bank.bic,
      "iban" => acc.iban,
      "kbe" => kbe && kbe.code,
      "knp" => knp && knp.code
    }

    %InvoiceBankSnapshot{}
    |> InvoiceBankSnapshot.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, snap} ->
        {:ok, snap}

      {:error, %Ecto.Changeset{} = cs} ->
        case Keyword.get(cs.errors, :invoice_id) do
          {_, opts} when is_list(opts) ->
            if Keyword.get(opts, :constraint) == :unique do
              {:error, :already_issued}
            else
              {:error, cs}
            end

          _ ->
            {:error, cs}
        end
    end
  end
end
